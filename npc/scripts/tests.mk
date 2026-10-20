# Active M5 S1 checks. Historical B1/Lite system targets are retired.
DIRECTED_TEST_FLAGS := --binary --timing --assert --sv -Wall -Wno-fatal -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD
LSU_TEST_OBJ := $(OBJ_DIR)/lsu
PRIMITIVE_TEST_OBJ := $(OBJ_DIR)/primitive
IFU_TEST_OBJ := $(OBJ_DIR)/ifu
EXU_TEST_OBJ := $(OBJ_DIR)/exu
.PHONY: lsu-test
lsu-test:
	verilator $(DIRECTED_TEST_FLAGS) \
		--top-module ysyx_lsu_tb --Mdir $(LSU_TEST_OBJ) \
		$(VSRC_DIR)/ysyx_lsu.sv $(NPC_HOME)/tests/ysyx_lsu_tb.sv
	$(LSU_TEST_OBJ)/Vysyx_lsu_tb

.PHONY: primitive-test
primitive-test:
	verilator $(DIRECTED_TEST_FLAGS) \
		--top-module ysyx_gnrl_buffer_tb --Mdir $(PRIMITIVE_TEST_OBJ) \
		$(NPC_HOME)/vsrc/gnrl/ysyx_gnrl_primitive.sv \
		$(NPC_HOME)/tests/ysyx_gnrl_buffer_tb.sv
	$(PRIMITIVE_TEST_OBJ)/Vysyx_gnrl_buffer_tb

.PHONY: ifu-test
ifu-test:
	verilator $(DIRECTED_TEST_FLAGS) \
		--top-module ysyx_ifu_tb --Mdir $(IFU_TEST_OBJ) \
		$(NPC_HOME)/vsrc/gnrl/ysyx_gnrl_primitive.sv \
		$(VSRC_DIR)/ysyx_ifu.sv $(NPC_HOME)/tests/ysyx_ifu_tb.sv
	$(IFU_TEST_OBJ)/Vysyx_ifu_tb

.PHONY: exu-test
exu-test:
	verilator $(DIRECTED_TEST_FLAGS) \
		--top-module ysyx_exu_tb --Mdir $(EXU_TEST_OBJ) \
		$(NPC_HOME)/vsrc/gnrl/ysyx_gnrl_primitive.sv \
		$(VSRC_DIR)/ysyx_alu.sv $(VSRC_DIR)/ysyx_branch.sv \
		$(VSRC_DIR)/ysyx_exu.sv $(NPC_HOME)/tests/ysyx_exu_tb.sv
	$(EXU_TEST_OBJ)/Vysyx_exu_tb

# Run identical reset/state checks with simulation and implementation defines.
architectural-state-test:
	@set -e; for profile in simulation synthesis; do \
	 defs=''; if [ "$$profile" = synthesis ]; then defs='-DSYNTHESIS -DNPC_SIM_DPI'; fi; \
	 verilator --binary --timing --assert --sv -Wall -Wno-TIMESCALEMOD \
	  $$defs --top-module ysyx_architectural_state_tb \
	  --Mdir $(OBJ_DIR)/state-$$profile \
	  $(NPC_HOME)/vsrc/gnrl/ysyx_gnrl_primitive.sv \
	  $(VSRC_DIR)/ysyx_regfile.sv $(VSRC_DIR)/ysyx_csr.sv \
	  $(NPC_HOME)/tests/ysyx_architectural_state_tb.sv; \
	 $(OBJ_DIR)/state-$$profile/Vysyx_architectural_state_tb; \
	done


.PHONY: idu-contract-test isa-contract-test
idu-contract-test:
	verilator --cc --exe --build --sv -Wall --top-module ysyx_idu \
	 --Mdir $(OBJ_DIR)/idu-contract-test \
	 $(VSRC_DIR)/ysyx_idu.sv $(NPC_HOME)/tests/idu_contract_tb.cpp
	$(OBJ_DIR)/idu-contract-test/Vysyx_idu


.PHONY: s1-test s1-protocol-test s1-cpu-test s1-elaboration-test isa-contract-test
s1-test: primitive-test ifu-test lsu-test exu-test architectural-state-test idu-contract-test
	python3 tests/m5_s1_test.py
s1-protocol-test:
	python3 tests/m5_s1_test.py --part protocol
s1-cpu-test:
	python3 tests/m5_s1_test.py --part cpu
s1-elaboration-test:
	python3 tests/m5_s1_test.py --part elaboration
isa-contract-test: idu-contract-test architectural-state-test exu-test s1-cpu-test
# Give historical scripts an actionable failure instead of building stale RTL.
b1-% axi4lite-%:
	@echo 'Retired platform test. Use make s1-test; historical reproduction requires the M4/S0 revision.'
	@exit 2

.PHONY: architectural-state-test
primitive-test ifu-test lsu-test exu-test architectural-state-test idu-contract-test: | $(OBJ_DIR)
$(OBJ_DIR):
	mkdir -p $@

.PHONY: access-fault-test address-misaligned-test synthesis-scope-check seed-regress
access-fault-test address-misaligned-test: s1-cpu-test
synthesis-scope-check:
	@echo 'M4 synthesis scope retired; S1 checks SYNTHESIS elaboration via s1-elaboration-test. New DC/PT scope is M5 S7.'
	@exit 2
seed-regress:
	@echo 'Legacy RAM harness retired; use s1-protocol-test / s1-cpu-test for fixed-seed AXI tests.'
	@exit 2
