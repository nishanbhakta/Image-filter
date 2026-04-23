#!/usr/bin/env python3
"""Run image preprocessing plus generated-data Verilog simulation in one command."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

import compare_feature_maps
import preprocess_image


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "generated_data"
DEFAULT_SIM_OUTPUT = REPO_ROOT / "sim_output" / "cnn_generated.vvp"
DEFAULT_WAVEFORM_OUTPUT = REPO_ROOT / "sim_output" / "waveforms" / "cnn_generated_tb.vcd"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Preprocess a real image, generate Verilog input data, compile the "
            "CNN accelerator testbench, and run the simulation."
        )
    )
    parser.add_argument("image", type=Path, help="Path to the input image")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory for generated preprocessing outputs (default: generated_data)",
    )
    parser.add_argument(
        "--resize",
        type=preprocess_image.parse_resize,
        help="Resize the grayscale image before window extraction, e.g. 28x28",
    )
    parser.add_argument(
        "--kernel",
        type=preprocess_image.parse_kernel,
        default=preprocess_image.parse_kernel("1,0,-1,1,0,-1,1,0,-1"),
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
        default=None,
        help="Maximum number of windows to include in the generated Verilog include (default: all emitted windows)",
    )
    parser.add_argument(
        "--iverilog",
        type=Path,
        help="Optional explicit path to iverilog.exe",
    )
    parser.add_argument(
        "--vvp",
        type=Path,
        help="Optional explicit path to vvp.exe",
    )
    parser.add_argument(
        "--sim-output",
        type=Path,
        default=DEFAULT_SIM_OUTPUT,
        help="Output .vvp file path (default: sim_output/cnn_generated.vvp)",
    )
    parser.add_argument(
        "--waveform-output",
        type=Path,
        default=DEFAULT_WAVEFORM_OUTPUT,
        help="Output VCD waveform path (default: sim_output/waveforms/cnn_generated_tb.vcd)",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help=(
            "Only generate the input/golden data files and Vivado handoff files. "
            "Do not run the Icarus simulation."
        ),
    )
    return parser.parse_args()


def resolve_executable(tool_name: str, explicit_path: Path | None, fallback_name: str) -> str:
    if explicit_path is not None:
        if not explicit_path.exists():
            raise FileNotFoundError(f"{tool_name} not found at: {explicit_path}")
        return str(explicit_path)

    discovered = shutil.which(fallback_name)
    if discovered is not None:
        return discovered

    if tool_name == "iverilog":
        fallback = Path(r"C:\iverilog\bin\iverilog.exe")
    else:
        fallback = Path(r"C:\iverilog\bin\vvp.exe")

    if fallback.exists():
        return str(fallback)

    raise FileNotFoundError(
        f"Could not find {tool_name}. Add it to PATH or pass --{tool_name} explicitly."
    )


def run_command(command: list[str], cwd: Path) -> None:
    print("", flush=True)
    print("Running:", flush=True)
    print("  " + " ".join(f'"{part}"' if " " in part else part for part in command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def resolve_path(path: Path) -> Path:
    return path if path.is_absolute() else (Path.cwd() / path).resolve()


def verilog_define_string(path: Path) -> str:
    return path.resolve().as_posix()


def main() -> int:
    args = parse_args()
    output_dir = resolve_path(args.output_dir)
    sim_output = resolve_path(args.sim_output)
    waveform_output = resolve_path(args.waveform_output)
    output_csv = output_dir / "output.csv"
    output_trace_csv = output_dir / "output_trace.csv"
    comparison_csv = output_dir / "output_comparison.csv"
    output_int16_stream_csv = output_dir / "output_int16_stream.csv"
    output_int16_mem = output_dir / "output_int16.mem"
    board_results_include = output_dir / "generated_board_results.vh"

    try:
        preprocess_result = preprocess_image.process_image(
            image_path=args.image.resolve(),
            output_dir=output_dir,
            resize=args.resize,
            kernel=args.kernel,
            scale_factor=args.scale_factor,
            limit_windows=args.limit_windows,
            verilog_window_limit=args.verilog_window_limit,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if args.prepare_only:
        print(f"Processed image: {preprocess_result['image_path']}", flush=True)
        print(f"Windows available: {preprocess_result['total_windows']}", flush=True)
        print(f"Windows prepared: {preprocess_result['verilog_windows']}", flush=True)
        print(
            "Output feature map size: "
            f"{preprocess_result['output_width']}x{preprocess_result['output_height']}",
            flush=True,
        )
        print(f"Generated data dir: {output_dir}", flush=True)
        print(f"Input CSV: {preprocess_result['input_windows_csv']}", flush=True)
        print(f"Golden output CSV: {preprocess_result['golden_output_csv']}", flush=True)
        print(f"Generated include: {preprocess_result['verilog_include']}", flush=True)
        print(
            "Open in Vivado: "
            f'vivado -mode gui -source vivado/run_generated_image_sim.tcl -tclargs "{output_dir}"',
            flush=True,
        )
        return 0

    try:
        iverilog = resolve_executable("iverilog", args.iverilog, "iverilog")
        vvp = resolve_executable("vvp", args.vvp, "vvp")
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    sim_output.parent.mkdir(parents=True, exist_ok=True)
    waveform_output.parent.mkdir(parents=True, exist_ok=True)

    print(f"Processed image: {preprocess_result['image_path']}", flush=True)
    print(f"Windows available: {preprocess_result['total_windows']}", flush=True)
    print(f"Windows to simulate: {preprocess_result['verilog_windows']}", flush=True)
    print(
        "Output feature map size: "
        f"{preprocess_result['output_width']}x{preprocess_result['output_height']}",
        flush=True,
    )
    print(f"Generated data dir: {output_dir}", flush=True)

    compile_command = [
        iverilog,
        "-g2012",
        "-DUSE_GENERATED_IMAGE_DATA",
        f'-DCNN_VCD_FILE="{verilog_define_string(waveform_output)}"',
        f'-DCNN_ACTUAL_OUTPUT_CSV="{verilog_define_string(output_csv)}"',
        f'-DCNN_ACTUAL_TRACE_CSV="{verilog_define_string(output_trace_csv)}"',
        "-I",
        str(preprocess_result["verilog_include"].parent),
        "-o",
        str(sim_output),
        "src/multiplier.v",
        "src/MAC.v",
        "src/divider_Version2.v",
        "src/divide_by_9_Version2.v",
        "src/controller_Version2.v",
        "src/cnn_accelerator_Version2.v",
        "tb/cnn_accelerator_tb_Version2.v",
    ]
    run_command(compile_command, cwd=REPO_ROOT)

    simulate_command = [vvp, str(sim_output)]
    run_command(simulate_command, cwd=REPO_ROOT)

    if not output_csv.exists():
        print(
            "Simulation completed but the hardware output CSV was not generated: "
            f"{output_csv}",
            file=sys.stderr,
        )
        return 1

    try:
        comparison_summary = compare_feature_maps.compare_feature_maps(
            golden_csv=preprocess_result["golden_output_csv"],
            actual_csv=output_csv,
            comparison_csv=comparison_csv,
        )
        board_export = preprocess_image.export_feature_map_as_int16_sequence(
            feature_map_csv=output_csv,
            stream_csv=output_int16_stream_csv,
            mem_path=output_int16_mem,
            verilog_include=board_results_include,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    print("", flush=True)
    print("Simulation complete.", flush=True)
    print(f"Input CSV: {preprocess_result['input_windows_csv']}", flush=True)
    print(f"Golden output CSV: {preprocess_result['golden_output_csv']}", flush=True)
    print(f"Hardware output CSV: {output_csv}", flush=True)
    print(f"Output trace CSV: {output_trace_csv}", flush=True)
    print(f"Comparison CSV: {comparison_csv}", flush=True)
    print(f"16-bit output stream CSV: {output_int16_stream_csv}", flush=True)
    print(f"16-bit output MEM: {output_int16_mem}", flush=True)
    print(f"Board results include: {board_results_include}", flush=True)
    print(f"Generated include: {preprocess_result['verilog_include']}", flush=True)
    print(f"Patch CSV: {preprocess_result['patches_csv']}", flush=True)
    print(f"Compiled simulation: {sim_output}", flush=True)
    print(f"Waveform (VCD): {waveform_output}", flush=True)
    print(
        "Open in Vivado: "
        f'vivado -mode gui -source vivado/run_generated_image_sim.tcl -tclargs "{output_dir}"',
        flush=True,
    )
    print(
        "Cross-check summary: "
        f"{comparison_summary['matching_cells']}/{comparison_summary['total_cells']} cells match, "
        f"{comparison_summary['mismatched_cells']} mismatches",
        flush=True,
    )
    print(
        "Board playback range: "
        f"{board_export['min_value']}..{board_export['max_value']} "
        f"across {board_export['count']} signed 16-bit results",
        flush=True,
    )
    print(f"Windows simulated: {preprocess_result['verilog_windows']}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
