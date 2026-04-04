# Nexys A7 CNN Block Design Report

This note aligns the project with the assignment brief for FPGA-friendly implementations of a 32x32 multiplier, divide-by-9 block, MAC, and 32-bit divider on a Nexys A7-class target.

## Nexys A7 Resource Snapshot

From the Digilent Nexys A7 reference manual:

| Variant | FPGA | LUTs | Flip-Flops | Block RAM | DSP Slices | CMTs |
|---|---|---:|---:|---:|---:|---:|
| Nexys A7-100T | XC7A100T-1CSG324C | 63,400 | 126,800 | 1,188 Kb | 240 | 6 |
| Nexys A7-50T | XC7A50T-1CSG324I | 32,600 | 65,200 | 600 Kb | 120 | 5 |

Useful board-level resources for this project:
- 100 MHz on-board oscillator
- 128 MiB DDR2 SDRAM
- USB-JTAG / USB-UART programming path
- GPIO peripherals including LEDs, switches, pushbuttons, seven-segment display, Pmods, VGA, Ethernet, and microSD

Official reference:
- Digilent Nexys A7 Reference Manual: https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf

## Chosen Implementations

### 1. 32x32 Multiplier

**Option A: DSP48-based multiplier**
- Best throughput and lowest latency because the synthesis tool maps `a * b` directly into DSP slices.
- Very attractive when DSP slices are plentiful and high throughput matters more than portability.
- The tradeoff is explicit DSP consumption, which is unnecessary for a small teaching-oriented design.

**Option B: combinational array / Wallace-tree multiplier**
- Produces a result in one cycle without DSP usage, but the logic depth is large and timing becomes harder.
- LUT cost is much higher than a sequential design, especially on a modest student project.
- This is usually the wrong default if area and implementation simplicity matter.

**Option C: sequential shift-add multiplier**
- Reuses one adder and a few shift registers over 32 cycles.
- Uses no DSP blocks, is easy to verify, and maps cleanly onto LUTs and FFs.
- Throughput is lower, but the area is predictable and fits the lab-style accelerator well.

**Recommended choice:** Option C, sequential shift-add.

Reason:
- It directly satisfies the "shift-add multiplier" requirement.
- It conserves DSP slices for later project extensions.
- It is small, deterministic, and easy to explain in a report and viva.

Implemented RTL:
- [multiplier.v](../src/multiplier.v)

Estimated implementation cost on Nexys A7:

| Metric | Estimate |
|---|---:|
| LUTs | 150-220 |
| FFs | 160-220 |
| DSPs | 0 |
| BRAM | 0 |
| Latency | 32 cycles |
| Initiation interval | 33 cycles |

### 2. Divide-by-9 Block

**Option A: reciprocal multiply**
- Multiply by a fixed-point approximation of `1/9` and shift down.
- Very fast and common in image-processing datapaths.
- Needs careful correction logic if exact signed truncation toward zero is required.

**Option B: constant restoring divider**
- Use long division with the divisor fixed at 9.
- Exact for positive and negative signed inputs and requires only compare/subtract/shift hardware.
- Slower than reciprocal multiply, but very easy to reason about and verify.

**Option C: LUT / piecewise approximation**
- Useful only for small input widths or approximate arithmetic.
- Not practical for a 72-bit signed datapath.
- It complicates correctness and does not scale cleanly.

**Recommended choice:** Option B, constant restoring divider.

Reason:
- Exact signed behavior is more important here than one-cycle speed.
- The datapath remains DSP-free and very transparent for a lab submission.
- The interface matches the general divider style used elsewhere in the project.

Implemented RTL:
- [divide_by_9_Version2.v](../src/divide_by_9_Version2.v)

Estimated implementation cost on Nexys A7:

| Metric | Estimate |
|---|---:|
| LUTs | 100-160 |
| FFs | 150-200 |
| DSPs | 0 |
| BRAM | 0 |
| Latency | 72 cycles |
| Initiation interval | 73 cycles |

### 3. MAC With 32-bit Inputs And 72-bit Accumulator

**Option A: DSP48 MAC**
- Maps multiply and accumulate into dedicated DSP resources.
- Gives the best throughput, often one result per cycle in a pipelined design.
- It is the right choice for performance-first CNN accelerators, but it consumes DSP budget quickly.

**Option B: shift-add multiplier plus accumulator**
- Uses the chosen sequential multiplier and accumulates the signed product into a 72-bit register.
- No DSP usage, easy control, and architectural consistency with the chosen multiplier.
- Latency is tied to the multiplier, but area remains modest.

**Option C: product-only accumulator helper**
- Accept a precomputed product and only perform the accumulation.
- Good as an internal helper in a staged pipeline.
- By itself it does not satisfy the assignment's "32-bit inputs MAC" requirement.

**Recommended choice:** Option B, shift-add multiplier plus accumulator.

Reason:
- It matches the requested 32-bit input MAC abstraction.
- It reuses the chosen multiplier architecture cleanly.
- It keeps the arithmetic path uniform and DSP-free.

Implemented RTL:
- Standalone MAC: [MAC.v](../src/MAC.v)
- Internal pipeline helper: [MAC.v](../src/MAC.v)

Estimated implementation cost on Nexys A7:

| Metric | Estimate |
|---|---:|
| LUTs | 230-320 |
| FFs | 250-340 |
| DSPs | 0 |
| BRAM | 0 |
| Latency | 33 cycles |
| Initiation interval | 34 cycles |

### 4. 32-bit Signed Divider

**Option A: restoring divider**
- Classical shift-subtract long division.
- Exact, compact, and straightforward to verify.
- Throughput is low, but it is an excellent baseline architecture.

**Option B: non-restoring divider**
- Saves some correction steps relative to the restoring approach.
- Can be a bit more efficient, but the control is harder to explain.
- Good if you want a slightly more advanced iterative divider.

**Option C: reciprocal/Newton-Raphson**
- Very fast for floating-point style or heavily pipelined systems.
- Overkill for a simple integer divider in a teaching project.
- Typically chosen only when throughput dominates every other concern.

**Recommended choice:** Option A, restoring divider.

Reason:
- It is exact, compact, and already a strong fit for the project's sequential style.
- It uses only simple arithmetic primitives.
- It is easier to defend in a project review than more aggressive iterative methods.

Implemented RTL:
- [divider_Version2.v](../src/divider_Version2.v)

Estimated implementation cost on Nexys A7:

| Metric | Estimate |
|---|---:|
| LUTs | 120-180 |
| FFs | 140-220 |
| DSPs | 0 |
| BRAM | 0 |
| Latency | 32 cycles |
| Initiation interval | 33 cycles |

## Accelerator-Level Notes

The top-level accelerator reuses:
- the sequential shift-add multiplier
- the lightweight pipeline accumulator helper
- the exact divide-by-9 block
- the signed restoring divider

Implemented top-level:
- [cnn_accelerator_Version2.v](../src/cnn_accelerator_Version2.v)

Expected top-level behavior:
- One 3x3 patch processed at a time
- Signed kernel and pixel support
- Rough end-to-end latency around 400 cycles per patch with the current control schedule
- Very low DSP demand, making the design easy to fit on either Nexys A7 variant

## Verification Status

The project includes passing standalone and integration simulations for:
- multiplier
- MAC
- divide-by-9
- 32-bit divider
- top-level CNN accelerator
- generated-image preprocessing plus simulation flow

## Notes On Estimates

The LUT/FF/DSP/BRAM values in this document are engineering estimates intended for assignment planning and architecture comparison. Final numbers depend on:
- Vivado version
- synthesis options
- target variant, speed grade, and constraints
- whether hierarchy is preserved or flattened

For a final submission, the next improvement would be to run Vivado synthesis on the chosen top modules and replace these estimates with measured post-synthesis utilization and timing.
