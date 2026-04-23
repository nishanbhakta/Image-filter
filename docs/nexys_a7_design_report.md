# Nexys A7 Arithmetic Design Report

This document maps the project to the assignment requirements for four required arithmetic blocks:
- 32x32 multiplier
- divide-by-9 unit
- 32-bit MAC with 72-bit accumulator
- 32-bit divider

## Final Architecture Choices

| Block | Final Choice | RTL File |
|---|---|---|
| 32x32 Multiplier | DSP-based multiplier | `src/multiplier.v` |
| Divide by 9 (32-bit) | Reciprocal multiply + correction | `src/divide_by_9_Version2.v` |
| MAC (32x32 -> 72-bit ACC) | DSP-based pipelined MAC | `src/MAC.v` |
| 32-bit Divider | Non-restoring divider | `src/divider_Version2.v` |

## Architecture Options and Tradeoffs

### 1) 32x32 Multiplier

Option A: DSP48-based multiplier
- Fastest and smallest LUT usage for this target.
- Natural FPGA mapping with predictable timing.

Option B: Combinational array / Wallace-tree
- Very high throughput, but larger logic depth and LUT cost.

Option C: Sequential shift-add
- Small area without DSPs, but high latency and low throughput.

Recommended: Option A (DSP-based).

### 2) Divide-by-9

Option A: Reciprocal multiply
- Uses constant reciprocal and correction logic.
- Excellent throughput with fixed divisor.

Option B: Repeated subtraction / restoring constant divider
- Exact but slower for wide datapaths.

Option C: Generic divider
- Flexible but overkill for constant 9.

Recommended: Option A (reciprocal multiply).

### 3) MAC

Option A: DSP MAC
- Highest throughput and best performance fit for FPGA.

Option B: Shift-add multiplier + accumulator
- Lower performance, no DSP dependency.

Option C: Product input + accumulator only
- Useful helper block but not a complete A/B MAC by itself.

Recommended: Option A (DSP MAC).

### 4) 32-bit Divider

Option A: Restoring divider
- Simple baseline, exact, deterministic.

Option B: Non-restoring divider
- Similar area, cleaner average datapath activity, deterministic latency.

Option C: Reciprocal/Newton style
- Best for high-throughput math pipelines, overkill for this requirement.

Recommended: Option B (non-restoring divider).

## Synthesizable RTL Status

Implemented and verified in simulation:
- `src/multiplier.v`
- `src/divide_by_9_Version2.v`
- `src/MAC.v`
- `src/divider_Version2.v`

Top-level integration using these blocks is in:
- `src/cnn_accelerator_Version2.v`
- `src/controller_Version2.v`

## Performance Estimates (Vivado 2025.2, xc7a100tcsg324-1, 10 ns clock)

### 32x32 DSP Multiplier

Reports:
- `vivado_build/arithmetic_reports/multiplier_util.rpt`
- `vivado_build/arithmetic_reports/multiplier_timing.rpt`

| Metric | Value |
|---|---:|
| LUTs | 47 |
| FFs | 100 |
| DSPs | 4 |
| BRAM | 0 |
| Latency | 1 cycle |
| Initiation Interval | 1 cycle |
| WNS @ 100 MHz | +6.437 ns |
| Approx Fmax | 280.7 MHz |

### Divide-by-9 Reciprocal (32-bit Required Block)

Reports:
- `vivado_build/arithmetic_reports/divide_by_9_u32_util.rpt`
- `vivado_build/arithmetic_reports/divide_by_9_u32_timing.rpt`

| Metric | Value |
|---|---:|
| LUTs | 336 |
| FFs | 219 |
| DSPs | 4 |
| BRAM | 0 |
| Latency | 4 cycles |
| Initiation Interval | 1 cycle |
| WNS @ 100 MHz | +0.794 ns |
| Approx Fmax | 108.6 MHz |

Note:
The same module is also instantiated at `WIDTH=72` in the CNN top-level for precision retention, which is a tougher timing target than the required 32-bit block.

### DSP MAC (32-bit inputs, 72-bit accumulator)

Reports:
- `vivado_build/arithmetic_reports/mac_util.rpt`
- `vivado_build/arithmetic_reports/mac_timing.rpt`

| Metric | Value |
|---|---:|
| LUTs | 121 |
| FFs | 109 |
| DSPs | 4 |
| BRAM | 0 |
| Latency | 1 cycle |
| Initiation Interval | 1 cycle |
| WNS @ 100 MHz | +4.762 ns |
| Approx Fmax | 190.9 MHz |

### 32-bit Non-Restoring Divider

Reports:
- `vivado_build/arithmetic_reports/divider_util.rpt`
- `vivado_build/arithmetic_reports/divider_timing.rpt`

| Metric | Value |
|---|---:|
| LUTs | 279 |
| FFs | 202 |
| DSPs | 0 |
| BRAM | 0 |
| Latency | 32 cycles |
| Initiation Interval | 33 cycles |
| WNS @ 100 MHz | +2.369 ns |
| Approx Fmax | 131.0 MHz |

## Verification

Passing simulations:
- multiplier testbench
- MAC testbench
- divide-by-9 testbench
- divider testbench
- CNN top-level directed testbench
- CNN CSV-driven regression

## Notes on Board-Level Metrics

These are synthesis/OOC metrics for arithmetic cores and are suitable for architecture comparison. Final routed board-level values will vary with top-level I/O, placement, and implementation settings.
