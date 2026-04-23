#!/usr/bin/env python3
"""Run image-to-CSV flow, launch Vivado, and display before/after CNN images.

Sequence:
1) Run scripts/run_image_sim.py for the input image.
2) Launch Vivado GUI with vivado/run_generated_image_sim.tcl.
3) Render and open before/after images from generated CSV outputs.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "generated_data"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run image preprocessing/simulation, open Vivado, and generate/view "
            "before-after CNN images."
        )
    )
    parser.add_argument("image", type=Path, help="Path to the input image")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Generated data directory (default: generated_data)",
    )
    parser.add_argument(
        "--resize",
        default="28x28",
        help="Resize in WIDTHxHEIGHT format passed to run_image_sim.py",
    )
    parser.add_argument(
        "--kernel",
        default="1,0,-1,1,0,-1,1,0,-1",
        help="3x3 kernel passed to run_image_sim.py",
    )
    parser.add_argument(
        "--scale-factor",
        type=int,
        default=1,
        help="Scale factor passed to run_image_sim.py",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help=(
            "Only run preprocessing and file generation in run_image_sim.py "
            "(no Icarus simulation)."
        ),
    )
    parser.add_argument(
        "--python-cmd",
        default="python",
        help="Python executable to use (default: python)",
    )
    parser.add_argument(
        "--vivado-cmd",
        default="vivado",
        help="Vivado executable to use (default: vivado)",
    )
    parser.add_argument(
        "--skip-vivado",
        action="store_true",
        help="Skip launching Vivado.",
    )
    parser.add_argument(
        "--skip-open-images",
        action="store_true",
        help="Generate image files but do not open them in a viewer.",
    )
    parser.add_argument(
        "--reset-runs",
        action="store_true",
        help="Clear existing Vivado synth/impl run outputs before launch.",
    )
    return parser.parse_args()


def resolve_tool(explicit: str, fallback: str) -> str:
    found = shutil.which(explicit)
    if found is not None:
        return found

    found_fallback = shutil.which(fallback)
    if found_fallback is not None:
        return found_fallback

    raise FileNotFoundError(f"Could not find executable: {explicit}")


def run_command(command: list[str], cwd: Path) -> None:
    print("", flush=True)
    print("Running:", flush=True)
    print("  " + " ".join(f'"{item}"' if " " in item else item for item in command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def open_path(path: Path) -> None:
    if sys.platform.startswith("win"):
        os.startfile(str(path))  # type: ignore[attr-defined]
        return

    launcher = "open" if sys.platform == "darwin" else "xdg-open"
    subprocess.Popen([launcher, str(path)])


def main() -> int:
    args = parse_args()
    output_dir = args.output_dir if args.output_dir.is_absolute() else (Path.cwd() / args.output_dir).resolve()
    image_path = args.image if args.image.is_absolute() else (Path.cwd() / args.image).resolve()

    if not image_path.exists():
        print(f"Input image not found: {image_path}", file=sys.stderr)
        return 1

    try:
        python_cmd = resolve_tool(args.python_cmd, "python")
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    run_sim_command = [
        python_cmd,
        str(REPO_ROOT / "scripts" / "run_image_sim.py"),
        str(image_path),
        "--output-dir",
        str(output_dir),
        "--resize",
        args.resize,
        "--kernel",
        args.kernel,
        "--scale-factor",
        str(args.scale_factor),
    ]
    if args.prepare_only:
        run_sim_command.append("--prepare-only")

    try:
        print("Step 1/3: Image to CSV + CNN pipeline", flush=True)
        run_command(run_sim_command, cwd=REPO_ROOT)
    except subprocess.CalledProcessError as exc:
        print(f"run_image_sim.py failed with code {exc.returncode}", file=sys.stderr)
        return exc.returncode or 1

    if not args.skip_vivado:
        try:
            vivado_cmd = resolve_tool(args.vivado_cmd, "vivado")
            vivado_command = [
                vivado_cmd,
                "-mode",
                "gui",
                "-source",
                str(REPO_ROOT / "vivado" / "run_generated_image_sim.tcl"),
                "-tclargs",
                str(output_dir),
            ]
            if args.reset_runs:
                vivado_command.append("--reset-runs")
            print("Step 2/3: Launch Vivado", flush=True)
            print(
                "  " + " ".join(f'"{item}"' if " " in item else item for item in vivado_command),
                flush=True,
            )
            subprocess.Popen(vivado_command, cwd=REPO_ROOT)
        except FileNotFoundError:
            print("Vivado executable not found; skipping launch.", file=sys.stderr)

    before_csv = output_dir / "grayscale_pixels.csv"
    after_csv = output_dir / "output.csv"
    if not after_csv.exists():
        # Fallback for prepare-only or when simulation output is unavailable.
        after_csv = output_dir / "golden_output.csv"

    output_png = output_dir / "cnn_before_after.png"
    csv_to_image_command = [
        python_cmd,
        str(REPO_ROOT / "scripts" / "csv_to_image.py"),
        str(before_csv),
        str(after_csv),
        "--output",
        str(output_png),
    ]

    try:
        print("Step 3/3: Render before/after images", flush=True)
        run_command(csv_to_image_command, cwd=REPO_ROOT)
    except subprocess.CalledProcessError as exc:
        print(f"csv_to_image.py failed with code {exc.returncode}", file=sys.stderr)
        return exc.returncode or 1

    before_png = output_png.with_name(f"{before_csv.stem}_image.png")
    after_png = output_png.with_name(f"{after_csv.stem}_image.png")

    print("", flush=True)
    print("Done.", flush=True)
    print(f"Before image : {before_png}", flush=True)
    print(f"After image  : {after_png}", flush=True)
    print(f"Combined     : {output_png}", flush=True)

    if not args.skip_open_images:
        for path in (before_png, after_png, output_png):
            if path.exists():
                open_path(path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
