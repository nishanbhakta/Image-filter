#!/usr/bin/env python3
"""Preprocess a real image into 3x3 windows for the CNN accelerator.

The script converts an image to grayscale, extracts all valid 3x3 patches
in row-major order, computes the accelerator's expected output for each
patch, and writes the results in formats that are easy to inspect or feed
into a Verilog testbench.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - dependency failure path
    raise SystemExit(
        "Pillow is required for image preprocessing. Install it with: pip install pillow"
    ) from exc


def parse_kernel(kernel_text: str) -> list[int]:
    cleaned = kernel_text.replace(",", " ").split()
    try:
        kernel = [int(value) for value in cleaned]
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"Kernel values must be integers: {kernel_text!r}"
        ) from exc

    if len(kernel) != 9:
        raise argparse.ArgumentTypeError(
            f"Kernel must contain exactly 9 values, received {len(kernel)}"
        )

    return kernel


def parse_resize(resize_text: str) -> tuple[int, int]:
    parts = resize_text.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(
            f"Resize must use WIDTHxHEIGHT format, received {resize_text!r}"
        )

    try:
        width = int(parts[0])
        height = int(parts[1])
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"Resize dimensions must be integers: {resize_text!r}"
        ) from exc

    if width < 3 or height < 3:
        raise argparse.ArgumentTypeError("Resize dimensions must both be at least 3")

    return width, height


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Convert an image into grayscale 3x3 windows and generate data for the "
            "CNN accelerator."
        )
    )
    parser.add_argument("image", type=Path, help="Path to the input image")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("preprocessed_output"),
        help="Directory for generated files (default: preprocessed_output)",
    )
    parser.add_argument(
        "--resize",
        type=parse_resize,
        help="Resize the grayscale image before window extraction, e.g. 28x28",
    )
    parser.add_argument(
        "--kernel",
        type=parse_kernel,
        default=parse_kernel("1,0,-1,1,0,-1,1,0,-1"),
        help=(
            "Comma- or space-separated 3x3 kernel values in row-major order "
            "(default: 1,0,-1,1,0,-1,1,0,-1)"
        ),
    )
    parser.add_argument(
        "--scale-factor",
        type=int,
        default=1,
        help="Final divisor used by the hardware model after divide-by-9 (default: 1)",
    )
    parser.add_argument(
        "--limit-windows",
        type=int,
        default=None,
        help="Only emit the first N windows if you want a smaller dataset",
    )
    parser.add_argument(
        "--verilog-window-limit",
        type=int,
        default=16,
        help=(
            "Maximum number of windows to include in the generated Verilog include "
            "(default: 16)"
        ),
    )
    return parser.parse_args()


def trunc_div(dividend: int, divisor: int) -> int:
    if divisor == 0:
        raise ValueError("Divisor cannot be zero")

    sign = -1 if (dividend < 0) ^ (divisor < 0) else 1
    return sign * (abs(dividend) // abs(divisor))


def verilog_literal(value: int) -> str:
    if value < 0:
        return f"-32'sd{abs(value)}"
    return f"32'sd{value}"


def load_grayscale_pixels(image_path: Path, resize: tuple[int, int] | None) -> list[list[int]]:
    with Image.open(image_path) as image:
        grayscale = image.convert("L")
        if resize is not None:
            grayscale = grayscale.resize(resize, Image.Resampling.LANCZOS)

        width, height = grayscale.size
        pixels = list(grayscale.getdata())

    return [pixels[row * width : (row + 1) * width] for row in range(height)]


def compute_patch_result(patch: list[int], kernel: list[int], scale_factor: int) -> int:
    accumulator = sum(pixel * weight for pixel, weight in zip(patch, kernel, strict=True))
    after_div9 = trunc_div(accumulator, 9)
    return trunc_div(after_div9, scale_factor)


def iter_patches(
    pixels: list[list[int]],
    kernel: list[int],
    scale_factor: int,
) -> Iterable[dict[str, int | list[int]]]:
    height = len(pixels)
    width = len(pixels[0])

    for row in range(height - 2):
        for col in range(width - 2):
            patch = [
                pixels[row + dr][col + dc]
                for dr in range(3)
                for dc in range(3)
            ]
            yield {
                "row": row,
                "col": col,
                "patch": patch,
                "expected_result": compute_patch_result(patch, kernel, scale_factor),
            }


def write_pixels_csv(path: Path, pixels: list[list[int]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        for row in pixels:
            writer.writerow(row)


def write_patches_csv(path: Path, patches: list[dict[str, int | list[int]]]) -> None:
    header = ["row", "col"] + [f"p{i}" for i in range(9)] + ["expected_result"]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        for patch_info in patches:
            writer.writerow(
                [
                    patch_info["row"],
                    patch_info["col"],
                    *patch_info["patch"],
                    patch_info["expected_result"],
                ]
            )


def write_metadata_json(
    path: Path,
    image_path: Path,
    pixels: list[list[int]],
    kernel: list[int],
    scale_factor: int,
    total_windows: int,
    emitted_windows: int,
    verilog_windows: int,
) -> None:
    metadata = {
        "source_image": str(image_path),
        "image_width": len(pixels[0]),
        "image_height": len(pixels),
        "kernel": kernel,
        "scale_factor": scale_factor,
        "total_windows_available": total_windows,
        "windows_emitted": emitted_windows,
        "windows_in_verilog_include": verilog_windows,
        "patch_order": "row-major",
        "formula": "result = trunc_toward_zero(trunc_toward_zero(sum(xi*hi)/9)/scale_factor)",
    }
    path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")


def write_verilog_include(
    path: Path,
    kernel: list[int],
    scale_factor: int,
    patches: list[dict[str, int | list[int]]],
) -> None:
    lines = [
        "`ifndef GENERATED_CNN_IMAGE_DATA_VH",
        "`define GENERATED_CNN_IMAGE_DATA_VH",
        "",
        "// Generated by scripts/preprocess_image.py",
        f"localparam integer GENERATED_NUM_WINDOWS = {len(patches)};",
        f"localparam signed [31:0] GENERATED_SCALE_FACTOR = {verilog_literal(scale_factor)};",
        "reg signed [31:0] generated_kernel [0:8];",
        "reg signed [31:0] generated_image_windows [0:GENERATED_NUM_WINDOWS-1][0:8];",
        "reg signed [31:0] generated_expected_results [0:GENERATED_NUM_WINDOWS-1];",
        "integer generated_window_rows [0:GENERATED_NUM_WINDOWS-1];",
        "integer generated_window_cols [0:GENERATED_NUM_WINDOWS-1];",
        "",
        "initial begin",
    ]

    for index, value in enumerate(kernel):
        lines.append(f"    generated_kernel[{index}] = {verilog_literal(value)};")

    if patches:
        lines.append("")

    for window_index, patch_info in enumerate(patches):
        lines.append(f"    generated_window_rows[{window_index}] = {patch_info['row']};")
        lines.append(f"    generated_window_cols[{window_index}] = {patch_info['col']};")
        patch_values = patch_info["patch"]
        for patch_index, value in enumerate(patch_values):
            lines.append(
                "    generated_image_windows"
                f"[{window_index}][{patch_index}] = {verilog_literal(value)};"
            )
        lines.append(
            "    generated_expected_results"
            f"[{window_index}] = {verilog_literal(patch_info['expected_result'])};"
        )
        lines.append("")

    lines.extend(["end", "", "`endif"])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def process_image(
    image_path: Path,
    output_dir: Path,
    resize: tuple[int, int] | None,
    kernel: list[int],
    scale_factor: int,
    limit_windows: int | None,
    verilog_window_limit: int,
) -> dict[str, object]:
    if not image_path.exists():
        raise FileNotFoundError(f"Input image not found: {image_path}")

    if scale_factor == 0:
        raise ValueError("Scale factor cannot be zero")

    if limit_windows is not None and limit_windows < 1:
        raise ValueError("limit-windows must be at least 1")

    if verilog_window_limit < 1:
        raise ValueError("verilog-window-limit must be at least 1")

    pixels = load_grayscale_pixels(image_path, resize)
    height = len(pixels)
    width = len(pixels[0])

    if width < 3 or height < 3:
        raise ValueError("Image must be at least 3x3 after preprocessing")

    all_patches = list(iter_patches(pixels, kernel, scale_factor))
    emitted_patches = (
        all_patches[:limit_windows] if limit_windows is not None else all_patches
    )
    verilog_patches = emitted_patches[:verilog_window_limit]

    output_dir.mkdir(parents=True, exist_ok=True)

    pixels_csv = output_dir / "grayscale_pixels.csv"
    patches_csv = output_dir / "patches.csv"
    metadata_json = output_dir / "metadata.json"
    verilog_include = output_dir / "generated_windows.vh"

    write_pixels_csv(pixels_csv, pixels)
    write_patches_csv(patches_csv, emitted_patches)
    write_metadata_json(
        metadata_json,
        image_path,
        pixels,
        kernel,
        scale_factor,
        total_windows=len(all_patches),
        emitted_windows=len(emitted_patches),
        verilog_windows=len(verilog_patches),
    )
    write_verilog_include(verilog_include, kernel, scale_factor, verilog_patches)

    return {
        "image_path": image_path,
        "width": width,
        "height": height,
        "kernel": kernel,
        "scale_factor": scale_factor,
        "total_windows": len(all_patches),
        "emitted_windows": len(emitted_patches),
        "verilog_windows": len(verilog_patches),
        "pixels_csv": pixels_csv,
        "patches_csv": patches_csv,
        "metadata_json": metadata_json,
        "verilog_include": verilog_include,
        "first_patch": emitted_patches[0] if emitted_patches else None,
    }


def main() -> int:
    args = parse_args()

    try:
        result = process_image(
            image_path=args.image,
            output_dir=args.output_dir,
            resize=args.resize,
            kernel=args.kernel,
            scale_factor=args.scale_factor,
            limit_windows=args.limit_windows,
            verilog_window_limit=args.verilog_window_limit,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print(f"Processed image: {result['image_path']}")
    print(f"Grayscale size: {result['width']}x{result['height']}")
    print(f"Kernel: {result['kernel']}")
    print(f"Scale factor: {result['scale_factor']}")
    print(f"Total 3x3 windows available: {result['total_windows']}")
    print(f"Windows written to CSV: {result['emitted_windows']}")
    print(f"Windows written to Verilog include: {result['verilog_windows']}")
    print(f"Wrote: {result['pixels_csv']}")
    print(f"Wrote: {result['patches_csv']}")
    print(f"Wrote: {result['metadata_json']}")
    print(f"Wrote: {result['verilog_include']}")

    if result["first_patch"] is not None:
        first_patch = result["first_patch"]
        print("First patch:")
        print(f"  position = ({first_patch['row']}, {first_patch['col']})")
        print(f"  values   = {first_patch['patch']}")
        print(f"  expected = {first_patch['expected_result']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
