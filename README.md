# CNN Hardware Accelerator

A Verilog implementation of a small CNN-style accelerator that computes:

```text
output = (sum(xi * hi)) / 9 / K
```

Where:
- `xi` = a 3x3 image patch flattened into 9 signed values
- `hi` = a 3x3 kernel flattened into 9 signed values
- `K` = scale factor

The hardware uses truncation toward zero for both division stages. The 3x3 sum and the
post-`/9` value stay at the full 72-bit accumulator width until the final result is
reduced back to the 32-bit output.

## Architecture

### Core modules

1. **cnn_accelerator_Version2.v** - parallel-product datapath with staged reduction and exact sequential normalization
2. **controller_Version2.v** - FSM for parallel multiply, reduction stages, divide-by-9, and final divide
3. **multiplier.v** - 32x32 signed DSP-oriented pipelined multiplier
4. **MAC.v** - standalone DSP-oriented 32x32-to-72-bit pipelined MAC plus accumulator helper
5. **divide_by_9_Version2.v** - signed reciprocal-multiply divide-by-9 with correction pipeline
6. **divider_Version2.v** - parameterized signed non-restoring divider
7. **uart_tx.v / uart_result_streamer.v** - board-level UART result transmitter

### Project layout

```text
CNN/
|-- docs/
|-- scripts/
|-- sim_output/
|-- src/
|-- tb/
|-- Makefile
|-- sim.bat
`-- README.md
```

## What Matches The Assignment

- DSP-based 32x32 multiplier RTL is implemented in [src/multiplier.v](src/multiplier.v)
- Reciprocal-multiply divide-by-9 with correction is implemented in [src/divide_by_9_Version2.v](src/divide_by_9_Version2.v)
- Standalone 32-bit-input, 72-bit-accumulator MAC is implemented in [src/MAC.v](src/MAC.v)
- Signed non-restoring divider is implemented in [src/divider_Version2.v](src/divider_Version2.v)
- Standalone and top-level simulations pass with Icarus Verilog

The assignment-oriented design discussion, Nexys A7 resource summary, and updated area/performance tables are in [docs/nexys_a7_design_report.md](docs/nexys_a7_design_report.md). Current Vivado arithmetic-core reports are under [vivado_build/arithmetic_reports](vivado_build/arithmetic_reports).

## Simulation

### Windows

Run the top-level testbench:

```powershell
.\sim.bat cnn
```

Run the CSV-driven top-level testbench with a richer dataset and visible accuracy summary:

```powershell
.\sim.bat cnn_csv
```

Run all component benches:

```powershell
.\sim.bat all
```

Available `sim.bat` targets:

- `cnn` - directed top-level regression
- `cnn_csv` - CSV-driven top-level regression using `tb/data/cnn_complex_vectors.csv`
- `multiplier`, `mac`, `divider`, `div9`, `uart` - individual module benches
- `all` - runs every test target above

### Linux / macOS

```bash
make
make test_all
```

## Image-Driven Flow

You can preprocess a real image into 3x3 windows and run the generated-data simulation in one command:

```powershell
py -3 scripts\run_image_sim.py path\to\image.png --resize 28x28 --kernel "1,0,-1,1,0,-1,1,0,-1" --scale-factor 1
```

This generates:
- grayscale pixel CSV
- patch CSV with pixels, kernel, intermediate math, and expected outputs
- input-window CSV for the Vivado handoff
- metadata JSON describing the image size, kernel, and window counts
- Verilog include file for the generated windows
- golden output feature-map CSV for reference checking
- hardware `output.csv` written by the generated-image testbench
- per-window `output_trace.csv`
- output comparison CSV for quick cross-verification
- compiled simulation output in `sim_output/`

Useful options for the image flow:

- `--limit-windows N` limits how many windows are written to the CSV outputs
- `--verilog-window-limit N` limits how many windows are compiled into the generated Verilog include, and if omitted all emitted windows are simulated
- `--output-dir path\to\dir` changes the generated-data directory
- `--prepare-only` stops after generating `input_windows.csv`, `golden_output.csv`, and the Vivado handoff files

### Vivado Waveform View

If you want the Python step to only prepare the files for Vivado, run:

```powershell
py -3 scripts\run_image_sim.py path\to\image.png --resize 28x28 --prepare-only
```

Then open Vivado and run the generated-image testbench:

```powershell
vivado -mode gui -source vivado/run_generated_image_sim.tcl -tclargs generated_data
```

If you used a custom output directory, pass that directory instead of `generated_data`.

The Vivado script:
- opens or creates a saved Vivado simulation project under `vivado_build/`
- points `cnn_accelerator_tb` at your generated `generated_windows.vh`
- enables `USE_GENERATED_IMAGE_DATA`
- launches behavioral simulation
- adds common top-level and DUT waves
- writes `output.csv` and `output_trace.csv` into the generated-data folder
- runs the Python comparison helper to produce `output_comparison.csv`
- keeps the waveform open in Vivado so you can inspect the hardware trace

## Parameters

```verilog
parameter WIDTH = 32
parameter ACC_WIDTH = 72
parameter NUM_INPUTS = 9
```

## Performance Notes

- Multiplier latency: 1 cycle, initiation interval 1 cycle
- Standalone MAC latency: 1 cycle, initiation interval 1 cycle
- Divide-by-9 latency: 4 cycles, initiation interval 1 cycle
- General divider latency: WIDTH cycles, so 32 cycles for the standalone divider and 72 cycles for the top-level final scaling stage
- Top-level accelerator latency: about 40 cycles per patch in the current single-patch control schedule
- DSP usage in the chosen arithmetic path: enabled for multiplier/MAC/divide-by-9 reciprocal path

## Next Steps

- Add routed implementation reports for the board wrapper with the accelerator demo path selected
- Add UART receive-side commands so patches and kernels can be loaded from a host PC
- Add an output feature-map writer so image simulations can emit reconstructed output images
