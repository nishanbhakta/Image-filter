# CNN Hardware Accelerator

A Verilog implementation of a small CNN-style accelerator that computes:

```text
output = (sum(xi * hi)) / 9 / K
```

Where:
- `xi` = a 3x3 image patch flattened into 9 signed values
- `hi` = a 3x3 kernel flattened into 9 signed values
- `K` = scale factor

## Architecture

### Core modules

1. **cnn_accelerator_Version2.v** - top-level datapath and control integration
2. **controller_Version2.v** - FSM for multiply, accumulate, divide-by-9, and final divide
3. **multiplier.v** - 32x32 signed sequential shift-add multiplier
4. **MAC.v** - standalone 32x32-to-72-bit MAC plus pipeline accumulator helper
5. **divide_by_9_Version2.v** - exact signed divide-by-9 using a constant restoring divider
6. **divider_Version2.v** - parameterized signed restoring divider

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

- Real shift-add multiplier RTL is implemented in [src/multiplier.v](src/multiplier.v)
- Exact divide-by-9 without `/` is implemented in [src/divide_by_9_Version2.v](src/divide_by_9_Version2.v)
- Standalone 32-bit-input, 72-bit-accumulator MAC is implemented in [src/MAC.v](src/MAC.v)
- Signed restoring divider is implemented in [src/divider_Version2.v](src/divider_Version2.v)
- Standalone and top-level simulations pass with Icarus Verilog

The assignment-oriented design discussion, Nexys A7 resource summary, and estimated area/performance tables are in [docs/nexys_a7_design_report.md](docs/nexys_a7_design_report.md).

## Simulation

### Windows

Run the top-level testbench:

```powershell
.\sim.bat cnn
```

Run all component benches:

```powershell
.\sim.bat all
```

### Linux / macOS

```bash
make
make test_all
```

## Image-Driven Flow

You can preprocess a real image into 3x3 windows and run the generated-data simulation in one command:

```powershell
python scripts\run_image_sim.py path\to\image.png --resize 28x28 --kernel "1,0,-1,1,0,-1,1,0,-1" --scale-factor 1
```

This generates:
- grayscale pixel CSV
- patch CSV with expected outputs
- Verilog include file for the generated windows
- compiled simulation output in `sim_output/`

## Parameters

```verilog
parameter WIDTH = 32
parameter ACC_WIDTH = 72
parameter NUM_INPUTS = 9
```

## Performance Notes

- Multiplier latency: 32 cycles
- Divide-by-9 latency: 72 cycles
- General divider latency: 32 cycles
- Top-level accelerator latency: roughly 400 cycles per 3x3 patch with the current sequential datapath
- DSP usage in the chosen arithmetic path: 0 DSP slices

## Next Steps

- Add Vivado synthesis reports for measured LUT/FF/DSP usage
- Add a board-level top module for Nexys A7 switches, buttons, UART, or VGA
- Add an output feature-map writer so image simulations can emit reconstructed output images
