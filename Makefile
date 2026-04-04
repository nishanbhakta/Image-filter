# CNN Accelerator Simulation Makefile
# Supports both Icarus Verilog and ModelSim/QuestaSim

# Compiler options
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Source directories
SRC_DIR = src
TB_DIR = tb

# Source files
SRCS = $(SRC_DIR)/multiplier.v \
       $(SRC_DIR)/MAC.v \
       $(SRC_DIR)/divider_Version2.v \
       $(SRC_DIR)/divide_by_9_Version2.v \
       $(SRC_DIR)/controller_Version2.v \
       $(SRC_DIR)/cnn_accelerator_Version2.v

# Testbench files
TB_MULTIPLIER = $(TB_DIR)/multiplier_tb_Version2.v
TB_MAC = $(TB_DIR)/mac_tb_Version2.v
TB_DIVIDER = $(TB_DIR)/divider_tb_Version2.v
TB_DIV9 = $(TB_DIR)/divide_by_9_Version2.v
TB_CNN = $(TB_DIR)/cnn_accelerator_tb_Version2.v

# Output files
OUT_DIR = sim_output
VCD_DIR = $(OUT_DIR)/waveforms

# Default target
.PHONY: all
all: cnn_accelerator

# Create output directories
$(OUT_DIR):
	mkdir -p $(OUT_DIR)
	mkdir -p $(VCD_DIR)

# CNN Accelerator simulation
.PHONY: cnn_accelerator
cnn_accelerator: $(OUT_DIR)
	@echo "=== Compiling CNN Accelerator ==="
	$(IVERILOG) -g2012 -o $(OUT_DIR)/cnn_accelerator.vvp $(SRCS) $(TB_CNN)
	@echo "=== Running CNN Accelerator Simulation ==="
	cd $(OUT_DIR) && $(VVP) cnn_accelerator.vvp
	@if [ -f cnn_accelerator_tb.vcd ]; then mv cnn_accelerator_tb.vcd $(VCD_DIR)/; fi
	@echo "=== Simulation Complete ==="
	@echo "Waveform saved to $(VCD_DIR)/cnn_accelerator_tb.vcd"

# Multiplier simulation
.PHONY: multiplier
multiplier: $(OUT_DIR)
	@echo "=== Compiling Multiplier ==="
	$(IVERILOG) -g2012 -o $(OUT_DIR)/multiplier.vvp $(SRC_DIR)/multiplier.v $(TB_MULTIPLIER)
	@echo "=== Running Multiplier Simulation ==="
	cd $(OUT_DIR) && $(VVP) multiplier.vvp
	@if [ -f multiplier_tb.vcd ]; then mv multiplier_tb.vcd $(VCD_DIR)/; fi

# MAC simulation
.PHONY: mac
mac: $(OUT_DIR)
	@echo "=== Compiling MAC ==="
	$(IVERILOG) -g2012 -o $(OUT_DIR)/mac.vvp $(SRC_DIR)/multiplier.v $(SRC_DIR)/MAC.v $(TB_MAC)
	@echo "=== Running MAC Simulation ==="
	cd $(OUT_DIR) && $(VVP) mac.vvp
	@if [ -f mac_tb.vcd ]; then mv mac_tb.vcd $(VCD_DIR)/; fi

# Divider simulation
.PHONY: divider
divider: $(OUT_DIR)
	@echo "=== Compiling Divider ==="
	$(IVERILOG) -g2012 -o $(OUT_DIR)/divider.vvp $(SRC_DIR)/divider_Version2.v $(TB_DIVIDER)
	@echo "=== Running Divider Simulation ==="
	cd $(OUT_DIR) && $(VVP) divider.vvp
	@if [ -f divider_tb.vcd ]; then mv divider_tb.vcd $(VCD_DIR)/; fi

# Divide-by-9 simulation
.PHONY: div9
div9: $(OUT_DIR)
	@echo "=== Compiling Divide-by-9 ==="
	$(IVERILOG) -g2012 -o $(OUT_DIR)/div9.vvp $(SRC_DIR)/divide_by_9_Version2.v $(TB_DIV9)
	@echo "=== Running Divide-by-9 Simulation ==="
	cd $(OUT_DIR) && $(VVP) div9.vvp
	@if [ -f divide_by_9_tb.vcd ]; then mv divide_by_9_tb.vcd $(VCD_DIR)/; fi

# Run all component tests
.PHONY: test_all
test_all: multiplier mac divider div9 cnn_accelerator
	@echo "=== All Tests Complete ==="

# View waveform
.PHONY: wave_cnn
wave_cnn:
	$(GTKWAVE) $(VCD_DIR)/cnn_accelerator_tb.vcd &

.PHONY: wave_mult
wave_mult:
	$(GTKWAVE) $(VCD_DIR)/multiplier_tb.vcd &

.PHONY: wave_mac
wave_mac:
	$(GTKWAVE) $(VCD_DIR)/mac_tb.vcd &

.PHONY: wave_div
wave_div:
	$(GTKWAVE) $(VCD_DIR)/divider_tb.vcd &

# Clean
.PHONY: clean
clean:
	rm -rf $(OUT_DIR)
	rm -f *.vcd *.vvp
	@echo "=== Cleaned simulation outputs ==="

# Help
.PHONY: help
help:
	@echo "CNN Accelerator Simulation Makefile"
	@echo "===================================="
	@echo "Targets:"
	@echo "  all (default)    - Run CNN accelerator simulation"
	@echo "  cnn_accelerator  - Run top-level CNN simulation"
	@echo "  multiplier       - Run multiplier testbench"
	@echo "  mac              - Run MAC testbench"
	@echo "  divider          - Run divider testbench"
	@echo "  div9             - Run divide-by-9 testbench"
	@echo "  test_all         - Run all testbenches"
	@echo "  wave_cnn         - View CNN waveform in GTKWave"
	@echo "  wave_mult        - View multiplier waveform"
	@echo "  wave_mac         - View MAC waveform"
	@echo "  wave_div         - View divider waveform"
	@echo "  clean            - Remove all simulation outputs"
	@echo "  help             - Show this help message"
