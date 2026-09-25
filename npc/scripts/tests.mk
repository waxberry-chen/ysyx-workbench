# Secondary verification targets.  Common build paths and the main Verilator
# binary are defined by the parent Makefile and scripts/build.mk.

RAM_SEEDS ?= 1 2 3 4 5 6 7 8 9 10
RAM_MAX_LATENCY ?= 7
RAM_READY_PERCENT ?= 50

DIRECTED_TEST_FLAGS := --binary --timing --assert --sv -Wall -Wno-fatal \
	-Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD

LSU_TEST_OBJ := $(OBJ_DIR)/lsu-test
PRIMITIVE_TEST_OBJ := $(OBJ_DIR)/primitive-test
IFU_TEST_OBJ := $(OBJ_DIR)/ifu-test
EXU_TEST_OBJ := $(OBJ_DIR)/exu-test

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

ACCESS_FAULT_TEST_DIR := $(OBJ_DIR)/access-fault-test
RISCV_GCC ?= riscv64-linux-gnu-gcc
RISCV_OBJCOPY ?= riscv64-linux-gnu-objcopy
ACCESS_FAULT_CFLAGS := -march=rv32i_zicsr -mabi=ilp32 -nostdlib \
	-nostartfiles -static -fno-pie -no-pie -Wl,--no-relax \
	-Wl,-e,_start -Wl,-Ttext=0x80000000

$(ACCESS_FAULT_TEST_DIR)/fetch.elf: $(NPC_HOME)/tests/access_fault.S
	@mkdir -p $(ACCESS_FAULT_TEST_DIR)
	$(RISCV_GCC) $(ACCESS_FAULT_CFLAGS) -DFAULT_KIND=1 -DFAULT_CAUSE=1 \
		-o $@ $<

$(ACCESS_FAULT_TEST_DIR)/load.elf: $(NPC_HOME)/tests/access_fault.S
	@mkdir -p $(ACCESS_FAULT_TEST_DIR)
	$(RISCV_GCC) $(ACCESS_FAULT_CFLAGS) -DFAULT_KIND=2 -DFAULT_CAUSE=5 \
		-o $@ $<

$(ACCESS_FAULT_TEST_DIR)/store.elf: $(NPC_HOME)/tests/access_fault.S
	@mkdir -p $(ACCESS_FAULT_TEST_DIR)
	$(RISCV_GCC) $(ACCESS_FAULT_CFLAGS) -DFAULT_KIND=3 -DFAULT_CAUSE=7 \
		-o $@ $<

$(ACCESS_FAULT_TEST_DIR)/%.bin: $(ACCESS_FAULT_TEST_DIR)/%.elf
	$(RISCV_OBJCOPY) -O binary --only-section=.text $< $@

.PHONY: access-fault-test
access-fault-test: $(VBIN) \
	$(ACCESS_FAULT_TEST_DIR)/fetch.bin \
	$(ACCESS_FAULT_TEST_DIR)/load.bin \
	$(ACCESS_FAULT_TEST_DIR)/store.bin
	@set -eu; \
	for kind in fetch load store; do \
		log=$(ACCESS_FAULT_TEST_DIR)/$$kind.log; \
		trace=$(ACCESS_FAULT_TEST_DIR)/$$kind.trace; \
		case $$kind in fetch) cause=1;; load) cause=5;; store) cause=7;; esac; \
		echo "Access fault $$kind -> $$log"; \
		$(VBIN) $(ARGS) -b --commit-trace=$$trace \
			$(ACCESS_FAULT_TEST_DIR)/$$kind.bin \
			> $$log 2>&1; \
		grep -q "HIT GOOD TRAP" $$log || { tail -40 $$log; exit 1; }; \
		grep -q "access error" $$log || { tail -40 $$log; exit 1; }; \
		grep -Eq " 1 0000000$$cause 1 " $$trace || { cat $$trace; exit 1; }; \
	done
	@echo "Instruction/load/store access fault tests: PASS"

# Re-run one deterministic image under several instruction-memory timing
# schedules.  Per-seed logs are build artifacts under build/seed-logs/.
.PHONY: seed-regress
seed-regress: $(VBIN) $(IMG)
	@mkdir -p $(OBJ_DIR)/seed-logs
	@set -eu; \
	for seed in $(RAM_SEEDS); do \
		log=$(OBJ_DIR)/seed-logs/seed-$$seed.log; \
		echo "RAM seed $$seed -> $$log"; \
		if ! $(VBIN) $(ARGS) -b \
			--ram-seed=$$seed \
			--ram-max-latency=$(RAM_MAX_LATENCY) \
			--ram-ready-percent=$(RAM_READY_PERCENT) \
			$(IMG) > $$log 2>&1; then \
			tail -40 $$log; exit 1; \
		fi; \
		grep -q "HIT GOOD TRAP" $$log || { tail -40 $$log; exit 1; }; \
	done
	@echo "All RAM seeds passed: $(RAM_SEEDS)"
