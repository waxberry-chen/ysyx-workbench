# Secondary verification targets.  Common build paths and the main Verilator
# binary are defined by the parent Makefile and scripts/build.mk.

.PHONY: b1-system-test
b1-system-test:
	$(MAKE) NPC_PLATFORM=b1 SRAM_BYTES=$(SRAM_BYTES) MTIME_HZ=$(MTIME_HZ) build
	python3 $(NPC_HOME)/tests/b1_system_test.py \
		--binary $(NPC_HOME)/build/b1-$(SRAM_BYTES)-$(MTIME_HZ)/Vysyx_b1_top \
		--out $(NPC_HOME)/build/b1-system-test-$(SRAM_BYTES)-$(MTIME_HZ) \
		--sram-bytes $(SRAM_BYTES) --mtime-hz $(MTIME_HZ)

RAM_SEEDS ?= 1 2 3 4 5 6 7 8 9 10
RAM_MAX_LATENCY ?= 7
RAM_READY_PERCENT ?= 50
AM_SMOKE_SECONDS ?= 10

AXI_SIGNOFF_DIR := $(OBJ_DIR)/axi4lite-signoff
AXI_CPU_TEST_DIR := $(NPC_HOME)/../am-kernels/tests/cpu-tests
AXI_HELLO_DIR := $(NPC_HOME)/../am-kernels/kernels/hello
AXI_YIELD_OS_DIR := $(NPC_HOME)/../am-kernels/kernels/yield-os
AXI_AM_TEST_DIR := $(NPC_HOME)/../am-kernels/tests/am-tests
AXI_CPU_TESTS := $(filter-out unalign,$(basename \
	$(notdir $(wildcard $(AXI_CPU_TEST_DIR)/tests/*.c))))
AXI_ADD_IMG := $(AXI_CPU_TEST_DIR)/build/add-riscv32e-npc.bin
# S2.5: M-only mstatus resets to 0x1800 (see 2.5-isa-contract.md for migration proof).
AXI_ARCH_TRACE_HASH := d18898e78483a270397c27594904e2fd520d84b7dc7c7dbac9401790f6d34392

DIRECTED_TEST_FLAGS := --binary --timing --assert --sv -Wall -Wno-fatal \
	-Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD

LSU_TEST_OBJ := $(OBJ_DIR)/lsu-test
PRIMITIVE_TEST_OBJ := $(OBJ_DIR)/primitive-test
IFU_TEST_OBJ := $(OBJ_DIR)/ifu-test
IFU_AXI_ADAPTER_TEST_OBJ := $(OBJ_DIR)/ifu-axi4lite-adapter-test
IFU_AXI_ADAPTER_INTEG_TEST_OBJ := $(OBJ_DIR)/ifu-axi4lite-adapter-integ-test
LSU_AXI_ADAPTER_TEST_OBJ := $(OBJ_DIR)/lsu-axi4lite-adapter-test
EXU_TEST_OBJ := $(OBJ_DIR)/exu-test
ADDRESS_MISALIGNED_TEST_DIR := $(OBJ_DIR)/address-misaligned-test

B1_ARBITER_TEST_OBJ := $(OBJ_DIR)/b1-arbiter-test
B1_ARBITER_RTL := $(NPC_HOME)/vsrc/bus/ysyx_axi4lite_arbiter.sv

# S1 is standalone: no changes to the legacy core/filelist or C++ RAM model.
# rst_n is asynchronous in state flops and sampled by disable-iff assertions;
# waive only that known SYNCASYNCNET diagnostic, keeping other warnings fatal.
.PHONY: b1-arbiter-lint b1-arbiter-test
b1-arbiter-lint:
	verilator --lint-only --sv -Wall --assert -Wno-SYNCASYNCNET \
		--top-module ysyx_axi4lite_arbiter $(B1_ARBITER_RTL)

b1-arbiter-test: b1-arbiter-lint
	@mkdir -p $(B1_ARBITER_TEST_OBJ)
	verilator --cc --exe --build --assert --sv -Wall -Wno-SYNCASYNCNET \
		--top-module ysyx_axi4lite_arbiter --Mdir $(B1_ARBITER_TEST_OBJ) \
		-CFLAGS '-std=c++14 -Wall -Wextra' \
		$(B1_ARBITER_RTL) $(NPC_HOME)/tests/axi4lite_arbiter_tb.cpp
	$(B1_ARBITER_TEST_OBJ)/Vysyx_axi4lite_arbiter \
		$(B1_ARBITER_TEST_OBJ)/coverage.csv

# S2 standalone routing and error sink; production filelist remains unchanged.
B1_XBAR_TEST_OBJ := $(OBJ_DIR)/b1-xbar-test
B1_DECERR_TEST_OBJ := $(OBJ_DIR)/b1-decerr-test
B1_XBAR_RTL := $(NPC_HOME)/vsrc/bus/ysyx_axi4lite_xbar.sv
B1_DECERR_RTL := $(NPC_HOME)/vsrc/bus/ysyx_axi4lite_decerr.sv
B1_XBAR_TOP := $(NPC_HOME)/tests/axi4lite_xbar_test_top.sv
# Test both the default capacity and a non-power-of-two range.
B1_TEST_SRAM_BYTES ?= 1048576
.PHONY: b1-xbar-lint b1-xbar-test b1-decerr-test
b1-xbar-lint:
	verilator --lint-only --sv -Wall --assert -Wno-SYNCASYNCNET \
		--top-module axi4lite_xbar_test_top -GSRAM_BYTES=$(B1_TEST_SRAM_BYTES) \
		$(B1_XBAR_RTL) $(B1_DECERR_RTL) $(B1_XBAR_TOP)

b1-xbar-test: b1-xbar-lint b1-decerr-test
	@mkdir -p $(B1_XBAR_TEST_OBJ)
	verilator --cc --exe --build --assert --sv -Wall -Wno-SYNCASYNCNET \
		--top-module axi4lite_xbar_test_top -GSRAM_BYTES=$(B1_TEST_SRAM_BYTES) \
		--Mdir $(B1_XBAR_TEST_OBJ) \
		-CFLAGS '-std=c++14 -Wall -Wextra -DTEST_SRAM_BYTES=$(B1_TEST_SRAM_BYTES)' \
		$(B1_XBAR_RTL) $(B1_DECERR_RTL) $(B1_XBAR_TOP) \
		$(NPC_HOME)/tests/axi4lite_xbar_tb.cpp
	$(B1_XBAR_TEST_OBJ)/Vaxi4lite_xbar_test_top $(B1_XBAR_TEST_OBJ)/coverage.csv

b1-decerr-test:
	@mkdir -p $(B1_DECERR_TEST_OBJ)
	verilator --cc --exe --build --assert --sv -Wall -Wno-SYNCASYNCNET \
		--top-module ysyx_axi4lite_decerr --Mdir $(B1_DECERR_TEST_OBJ) \
		-CFLAGS '-std=c++14 -Wall -Wextra' \
		$(B1_DECERR_RTL) $(NPC_HOME)/tests/axi4lite_decerr_tb.cpp
	$(B1_DECERR_TEST_OBJ)/Vysyx_axi4lite_decerr $(B1_DECERR_TEST_OBJ)/coverage.csv

.PHONY: b1-xbar-config-test
b1-xbar-config-test:
	python3 $(NPC_HOME)/tests/axi4lite_xbar_config_test.py $(OBJ_DIR)/b1-xbar-config-test

# S3 device tests; simulation preload/preset access stays in the testbench.
B1_SLAVES_OBJ := $(OBJ_DIR)/b1-slaves-test
B1_SLAVES_RTL := $(NPC_HOME)/vsrc/bus/ysyx_axi4lite_slave_frontend.sv \
	$(NPC_HOME)/vsrc/periph/ysyx_axi4lite_sram.sv \
	$(NPC_HOME)/vsrc/periph/ysyx_axi4lite_uart.sv \
	$(NPC_HOME)/vsrc/periph/ysyx_axi4lite_clint.sv
B1_SLAVES_TOP := $(NPC_HOME)/tests/axi4lite_slaves_test_top.sv
.PHONY: b1-slaves-lint b1-slaves-test
b1-slaves-lint:
	verilator --lint-only --sv -Wall --assert -Wno-SYNCASYNCNET \
		--top-module axi4lite_slaves_test_top -GSRAM_BYTES=$(B1_TEST_SRAM_BYTES) \
		$(B1_SLAVES_RTL) $(B1_SLAVES_TOP)

b1-slaves-test: b1-slaves-lint
	@mkdir -p $(B1_SLAVES_OBJ)
	verilator --cc --exe --build --assert --sv -Wall -Wno-SYNCASYNCNET \
		--top-module axi4lite_slaves_test_top -GSRAM_BYTES=$(B1_TEST_SRAM_BYTES) \
		--Mdir $(B1_SLAVES_OBJ) \
		-CFLAGS '-std=c++14 -Wall -Wextra -DTEST_SRAM_BYTES=$(B1_TEST_SRAM_BYTES)' \
		$(B1_SLAVES_RTL) $(B1_SLAVES_TOP) $(NPC_HOME)/tests/axi4lite_slaves_tb.cpp
	$(B1_SLAVES_OBJ)/Vaxi4lite_slaves_test_top $(B1_SLAVES_OBJ)/coverage.csv

.PHONY: b1-slaves-config-test
b1-slaves-config-test:
	python3 $(NPC_HOME)/tests/axi4lite_slaves_config_test.py $(OBJ_DIR)/b1-slaves-config-test

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

.PHONY: ifu-axi4lite-adapter-test
ifu-axi4lite-adapter-test:
	verilator $(DIRECTED_TEST_FLAGS) \
		--top-module ysyx_ifu_axi4lite_adapter_tb \
		--Mdir $(IFU_AXI_ADAPTER_TEST_OBJ) \
		$(NPC_HOME)/vsrc/bus/ysyx_ifu_axi4lite_adapter.sv \
		$(NPC_HOME)/tests/ysyx_ifu_axi4lite_adapter_tb.sv
	$(IFU_AXI_ADAPTER_TEST_OBJ)/Vysyx_ifu_axi4lite_adapter_tb

.PHONY: ifu-axi4lite-adapter-integ-test
ifu-axi4lite-adapter-integ-test:
	verilator $(DIRECTED_TEST_FLAGS) \
		--top-module ysyx_ifu_axi4lite_adapter_integ_tb \
		--Mdir $(IFU_AXI_ADAPTER_INTEG_TEST_OBJ) \
		$(NPC_HOME)/vsrc/gnrl/ysyx_gnrl_primitive.sv \
		$(VSRC_DIR)/ysyx_ifu.sv \
		$(NPC_HOME)/vsrc/bus/ysyx_ifu_axi4lite_adapter.sv \
		$(NPC_HOME)/tests/ysyx_ifu_axi4lite_adapter_integ_tb.sv
	$(IFU_AXI_ADAPTER_INTEG_TEST_OBJ)/Vysyx_ifu_axi4lite_adapter_integ_tb

.PHONY: lsu-axi4lite-adapter-test
lsu-axi4lite-adapter-test:
	verilator $(DIRECTED_TEST_FLAGS) \
		--top-module ysyx_lsu_axi4lite_adapter_tb \
		--Mdir $(LSU_AXI_ADAPTER_TEST_OBJ) \
		$(NPC_HOME)/vsrc/bus/ysyx_lsu_axi4lite_adapter.sv \
		$(NPC_HOME)/tests/ysyx_lsu_axi4lite_adapter_tb.sv
	$(LSU_AXI_ADAPTER_TEST_OBJ)/Vysyx_lsu_axi4lite_adapter_tb

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

$(ADDRESS_MISALIGNED_TEST_DIR)/load.elf: $(NPC_HOME)/tests/address_misaligned.S
	@mkdir -p $(ADDRESS_MISALIGNED_TEST_DIR)
	$(RISCV_GCC) $(ACCESS_FAULT_CFLAGS) -DFAULT_KIND=2 -DFAULT_CAUSE=4 \
		-o $@ $<

$(ADDRESS_MISALIGNED_TEST_DIR)/store.elf: $(NPC_HOME)/tests/address_misaligned.S
	@mkdir -p $(ADDRESS_MISALIGNED_TEST_DIR)
	$(RISCV_GCC) $(ACCESS_FAULT_CFLAGS) -DFAULT_KIND=3 -DFAULT_CAUSE=6 \
		-o $@ $<

$(ADDRESS_MISALIGNED_TEST_DIR)/%.bin: $(ADDRESS_MISALIGNED_TEST_DIR)/%.elf
	$(RISCV_OBJCOPY) -O binary --only-section=.text $< $@

.PHONY: address-misaligned-test
address-misaligned-test: $(VBIN) \
	$(ADDRESS_MISALIGNED_TEST_DIR)/load.bin \
	$(ADDRESS_MISALIGNED_TEST_DIR)/store.bin
	@set -eu; \
	for kind in load store; do \
		log=$(ADDRESS_MISALIGNED_TEST_DIR)/$$kind.log; \
		trace=$(ADDRESS_MISALIGNED_TEST_DIR)/$$kind.trace; \
		case $$kind in load) cause=4;; store) cause=6;; esac; \
		echo "Address-misaligned $$kind -> $$log"; \
		$(VBIN) $(ARGS) -b --commit-trace=$$trace \
			$(ADDRESS_MISALIGNED_TEST_DIR)/$$kind.bin \
			> $$log 2>&1; \
		grep -q "HIT GOOD TRAP" $$log || { tail -40 $$log; exit 1; }; \
		grep -q "D-RAM transactions: requests = 0 " $$log || \
			{ tail -40 $$log; exit 1; }; \
		grep -Eq " 1 0000000$$cause 1 " $$trace || \
			{ cat $$trace; exit 1; }; \
	done
	@echo "Load/store address-misaligned tests: PASS"

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

# AXI4-Lite milestone sign-off.  Keep the orchestration here rather than in
# the main Makefile so the default build interface remains small.
.PHONY: axi4lite-directed-regress
axi4lite-directed-regress:
	$(MAKE) lint primitive-test ifu-test lsu-test exu-test \
		ifu-axi4lite-adapter-test ifu-axi4lite-adapter-integ-test \
		lsu-axi4lite-adapter-test access-fault-test \
		address-misaligned-test

.PHONY: axi4lite-cpu-regress
axi4lite-cpu-regress:
	@set -eu; \
	mkdir -p $(AXI_SIGNOFF_DIR); \
	log=$(AXI_SIGNOFF_DIR)/cpu-tests.log; \
	$(MAKE) -C $(AXI_CPU_TEST_DIR) ARCH=riscv32e-npc \
		ALL="$(AXI_CPU_TESTS)" run > $$log 2>&1; \
	cat $$log; \
	if grep -q "FAIL" $$log; then exit 1; fi; \
	pass_count=$$(grep -c "PASS" $$log || true); \
	if [ $$pass_count -ne $(words $(AXI_CPU_TESTS)) ]; then \
		echo "Expected $(words $(AXI_CPU_TESTS)) CPU-test PASS lines, got $$pass_count"; \
		exit 1; \
	fi

.PHONY: axi4lite-trace-test
axi4lite-trace-test: $(VBIN)
	@set -eu; \
	test -f $(AXI_ADD_IMG) || { \
		echo "Missing $(AXI_ADD_IMG); run axi4lite-cpu-regress first"; \
		exit 1; \
	}; \
	mkdir -p $(AXI_SIGNOFF_DIR); \
	trace=$(AXI_SIGNOFF_DIR)/add.trace; \
	log=$(AXI_SIGNOFF_DIR)/add.log; \
	$(VBIN) $(ARGS) -b \
		--ram-seed=42 --ram-max-latency=3 --ram-ready-percent=75 \
		--commit-trace=$$trace $(AXI_ADD_IMG) > $$log 2>&1; \
	grep -q "HIT GOOD TRAP" $$log || { tail -40 $$log; exit 1; }; \
	grep -q "committed instructions = 1095" $$log || \
		{ tail -40 $$log; exit 1; }; \
	grep -q "I-RAM transactions: requests = 1310, responses = 1310" \
		$$log || { tail -40 $$log; exit 1; }; \
	grep -q "D-RAM transactions: requests = 282 (loads = 243, stores = 39), responses = 282" \
		$$log || { tail -40 $$log; exit 1; }; \
	arch_hash=$$(awk '!/^#/ {print $$1, $$2, $$3, $$4, $$5}' $$trace | \
		sha256sum | cut -d ' ' -f 1); \
	if [ "$$arch_hash" != "$(AXI_ARCH_TRACE_HASH)" ]; then \
		echo "Architectural trace hash mismatch:"; \
		echo "  expected $(AXI_ARCH_TRACE_HASH)"; \
		echo "  actual   $$arch_hash"; \
		exit 1; \
	fi; \
	echo "AXI4-Lite architectural trace: PASS ($$arch_hash)"

.PHONY: axi4lite-am-smoke
axi4lite-am-smoke:
	@set -eu; \
	mkdir -p $(AXI_SIGNOFF_DIR); \
	hello_log=$(AXI_SIGNOFF_DIR)/hello.log; \
	$(MAKE) -C $(AXI_HELLO_DIR) ARCH=riscv32e-npc run \
		mainargs=I-love-ysyx > $$hello_log 2>&1; \
	grep -q "Hello, AbstractMachine!" $$hello_log || \
		{ tail -40 $$hello_log; exit 1; }; \
	grep -q "mainargs = 'I-love-ysyx'." $$hello_log || \
		{ tail -40 $$hello_log; exit 1; }; \
	grep -q "HIT GOOD TRAP" $$hello_log || \
		{ tail -40 $$hello_log; exit 1; }; \
	echo "UART hello smoke test: PASS"; \
	rtc_log=$(AXI_SIGNOFF_DIR)/rtc.log; \
	status=0; \
	timeout $(AM_SMOKE_SECONDS)s $(MAKE) -C $(AXI_AM_TEST_DIR) \
		ARCH=riscv32e-npc run mainargs=t > $$rtc_log 2>&1 || status=$$?; \
	if [ $$status -ne 124 ] && [ $$status -ne 143 ]; then \
		tail -40 $$rtc_log; exit 1; \
	fi; \
	grep -q "GMT (" $$rtc_log || { tail -40 $$rtc_log; exit 1; }; \
	if grep -Eq "mismatch|Assertion failed|ABORT" $$rtc_log; then \
		tail -40 $$rtc_log; exit 1; \
	fi; \
	echo "RTC smoke test: PASS (expected timeout)"; \
	yield_log=$(AXI_SIGNOFF_DIR)/yield-os.log; \
	status=0; \
	timeout $(AM_SMOKE_SECONDS)s $(MAKE) -C $(AXI_YIELD_OS_DIR) \
		ARCH=riscv32e-npc run > $$yield_log 2>&1 || status=$$?; \
	if [ $$status -ne 124 ] && [ $$status -ne 143 ]; then \
		tail -40 $$yield_log; exit 1; \
	fi; \
	grep -q "ABAB" $$yield_log || { tail -40 $$yield_log; exit 1; }; \
	if grep -Eq "mismatch|Assertion failed|ABORT" $$yield_log; then \
		tail -40 $$yield_log; exit 1; \
	fi; \
	echo "yield-os smoke test: PASS (expected timeout)"

.PHONY: axi4lite-signoff
axi4lite-signoff:
	$(MAKE) axi4lite-directed-regress
	$(MAKE) axi4lite-cpu-regress
	$(MAKE) axi4lite-trace-test
	$(MAKE) seed-regress IMG=$(AXI_ADD_IMG) \
		RAM_SEEDS='$(RAM_SEEDS)' \
		RAM_MAX_LATENCY=$(RAM_MAX_LATENCY) \
		RAM_READY_PERCENT=$(RAM_READY_PERCENT)
	$(MAKE) axi4lite-am-smoke AM_SMOKE_SECONDS=$(AM_SMOKE_SECONDS)
	@echo "AXI4-Lite milestone sign-off: PASS"

# Full B1 fabric, using independent IFU/LSU drivers and actual RTL devices.
B1_FABRIC_DIR := $(NPC_HOME)/build/b1-fabric-test
B1_FABRIC_RTL := $(wildcard $(NPC_HOME)/vsrc/bus/ysyx_axi4lite_*.sv) \
 $(wildcard $(NPC_HOME)/vsrc/periph/ysyx_axi4lite_*.sv) \
 $(NPC_HOME)/tests/axi4lite_delay_shim.sv $(NPC_HOME)/tests/axi4lite_fabric_test_top.sv
.PHONY: b1-fabric-test
b1-fabric-test:
	verilator --cc --exe --build --trace --assert --sv -Wall -Wno-SYNCASYNCNET \
	 -Wno-DECLFILENAME --top-module axi4lite_fabric_test_top --Mdir $(B1_FABRIC_DIR) \
	 -CFLAGS '-std=c++14' $(B1_FABRIC_RTL) $(NPC_HOME)/tests/axi4lite_fabric_tb.cpp
	$(B1_FABRIC_DIR)/Vaxi4lite_fabric_test_top $(B1_FABRIC_DIR)/coverage.csv $(B1_FABRIC_DIR)/representative.vcd

.PHONY: b1-redirect-test
b1-redirect-test:
	verilator --cc --exe --build --assert --sv -Wall -Wno-SYNCASYNCNET \
	 --top-module axi4lite_redirect_test_top --Mdir $(NPC_HOME)/build/b1-redirect-test \
	 -CFLAGS '-std=c++14' $(NPC_HOME)/vsrc/gnrl/ysyx_gnrl_primitive.sv \
	 $(VSRC_DIR)/ysyx_ifu.sv $(NPC_HOME)/vsrc/bus/ysyx_ifu_axi4lite_adapter.sv \
	 $(B1_ARBITER_RTL) $(NPC_HOME)/tests/axi4lite_redirect_test_top.sv \
	 $(NPC_HOME)/tests/axi4lite_redirect_tb.cpp
	$(NPC_HOME)/build/b1-redirect-test/Vaxi4lite_redirect_test_top $(NPC_HOME)/build/b1-redirect-test/coverage.csv

.PHONY: b1-directed-regress b1-random-regress b1-system-regress b1-signoff
b1-directed-regress:
	$(MAKE) b1-arbiter-test b1-xbar-test b1-xbar-config-test b1-slaves-test b1-slaves-config-test b1-redirect-test ifu-axi4lite-adapter-integ-test
b1-random-regress:
	$(MAKE) b1-fabric-test
b1-system-regress:
	@test "$(SRAM_BYTES):$(MTIME_HZ):$(B1_SIM_SHIM)" = "1048576:1000000:0" || \
	 { echo 'S5 closure uses frozen SRAM_BYTES=1048576 MTIME_HZ=1000000 B1_SIM_SHIM=0; use b1-system-test for other configurations'; exit 1; }
	$(MAKE) b1-system-test
	$(MAKE) NPC_PLATFORM=b1 B1_SIM_SHIM=1 build
	python3 $(NPC_HOME)/tests/b1_closure_test.py
b1-signoff:
	@test "$(SRAM_BYTES):$(MTIME_HZ):$(B1_SIM_SHIM)" = "1048576:1000000:0" || \
	 { echo 'S5 signoff requires frozen SRAM_BYTES=1048576 MTIME_HZ=1000000 B1_SIM_SHIM=0'; exit 1; }
	$(MAKE) NPC_PLATFORM=legacy lint
	$(MAKE) NPC_PLATFORM=b1 lint
	$(MAKE) NPC_PLATFORM=b1 LINT_TOP=ysyx_core_axi4lite lint
	$(MAKE) b1-directed-regress
	$(MAKE) b1-random-regress
	$(MAKE) b1-system-regress
	$(MAKE) b1-coverage-check

.PHONY: b1-coverage-check
b1-coverage-check:
	python3 $(NPC_HOME)/tests/b1_coverage_check.py

.PHONY: synthesis-scope-check architectural-state-test
synthesis-scope-check:
	python3 $(NPC_HOME)/tests/synthesis_scope_check.py

# Run identical reset/state checks with simulation and implementation defines.
architectural-state-test:
	@set -e; for profile in simulation synthesis; do \
	 defs=''; if [ "$$profile" = synthesis ]; then defs='-DSYNTHESIS -DNPC_SIM_DPI'; fi; \
	 verilator --binary --timing --assert --sv -Wall -Wno-TIMESCALEMOD \
	  $$defs --top-module ysyx_architectural_state_tb \
	  --Mdir $(NPC_HOME)/build/m4-s1/state-$$profile \
	  $(NPC_HOME)/vsrc/gnrl/ysyx_gnrl_primitive.sv \
	  $(VSRC_DIR)/ysyx_regfile.sv $(VSRC_DIR)/ysyx_csr.sv \
	  $(NPC_HOME)/tests/ysyx_architectural_state_tb.sv; \
	 $(NPC_HOME)/build/m4-s1/state-$$profile/Vysyx_architectural_state_tb; \
	done

# S2.5: independent decoder oracle plus precise-trap software (both platforms).
.PHONY: idu-contract-test isa-contract-test
idu-contract-test:
	verilator --cc --exe --build --sv -Wall --top-module ysyx_idu \
	 --Mdir $(NPC_HOME)/build/idu-contract-test \
	 $(VSRC_DIR)/ysyx_idu.sv $(NPC_HOME)/tests/idu_contract_tb.cpp
	$(NPC_HOME)/build/idu-contract-test/Vysyx_idu

isa-contract-test: idu-contract-test architectural-state-test exu-test
	$(MAKE) -C $(NEMU_HOME) git_commit=
	$(MAKE) NPC_PLATFORM=legacy build
	$(MAKE) NPC_PLATFORM=b1 build
	python3 $(NPC_HOME)/tests/isa_contract_test.py
