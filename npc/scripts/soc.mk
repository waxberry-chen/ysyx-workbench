# Real SoC simulation. The peripheral models are already instantiated by Full.
SOC_HOME := $(abspath ../ysyxSoC)
SOC_BOOT ?= mrom
# Explicit build selection; all modes use identical software and monitor logic.
BPU_MODE ?= 2
SOC_BPU_FLAGS := -DNPC_BPU_MODE=$(BPU_MODE)
ifeq ($(SOC_BOOT),flash)
SOC_BUILD := $(NPC_HOME)/build/ysyxsoc-flash
SOC_BOOT_FLAGS := -DNPC_FLASH_BOOT
SOC_IMAGE_ARG := --flash
else ifeq ($(SOC_BOOT),mrom)
SOC_BUILD := $(NPC_HOME)/build/ysyxsoc
SOC_IMAGE_ARG := --mrom
else
$(error NPC SOC_BOOT must be mrom or flash)
endif
SOC_DELAY ?= 0
ifeq ($(SOC_DELAY),1)
SOC_BUILD := $(SOC_BUILD)-delay
SOC_FILELIST := $(SOC_BUILD)/filelist-delay.f
else ifeq ($(SOC_DELAY),0)
SOC_FILELIST := filelist-soc.f
else
$(error SOC_DELAY must be 0 or 1)
endif
SOC_RTL := $(SOC_HOME)/build/ysyxSoCFull.v
SOC_BINARY := $(SOC_BUILD)/VysyxSoCFull
SOC_PERIPH := $(shell rg --files $(SOC_HOME)/perip -g '*.v' | sort)
SOC_FLAGS := --cc --exe --build -j 2 --sv --timing --assert --trace-fst \
 --timescale-override 1ns/1ps -Wall -Wno-fatal -Wno-SYNCASYNCNET \
 -Werror-WIDTH -Werror-PINMISSING -Werror-PINNOTFOUND -Werror-LATCH \
 -Werror-UNOPTFLAT -Werror-UNDRIVEN --top-module ysyxSoCFull \
 -I$(SOC_HOME)/perip/uart16550/rtl -I$(SOC_HOME)/perip/spi/rtl \
 -F $(SOC_FILELIST) $(SOC_RTL) $(SOC_PERIPH) $(NPC_HOME)/sim/soc_monitor.sv $(NPC_HOME)/sim/bpu_monitor.sv \
 $(NPC_HOME)/csrc/soc/main.cpp $(NPC_HOME)/csrc/soc/difftest.cpp \
 $(SOC_BOOT_FLAGS) $(SOC_BPU_FLAGS) -CFLAGS '-std=c++17 -Wall -Wextra $(SOC_BOOT_FLAGS)' -LDFLAGS '-ldl' --Mdir $(SOC_BUILD)
.PHONY: soc-verilog soc-build build run sim s2-test
soc-verilog:
	$(MAKE) -C $(SOC_HOME) verilog
soc-build: soc-verilog
	mkdir -p $(SOC_BUILD)
ifeq ($(SOC_DELAY),1)
	python3 scripts/soc_delay.py --out $(SOC_BUILD)
endif
	verilator $(SOC_FLAGS)
build: soc-build
# Supply a raw MROM (<=4 KiB) or Flash (<=16 MiB) image. No RAM preload.
run sim: soc-build
	@test -n "$(IMG)" || { echo 'Use make -C npc run SOC_BOOT=mrom|flash IMG=/path/to/image.bin [ARGS="..."]'; exit 2; }
	$(SOC_BINARY) $(SOC_IMAGE_ARG) "$(IMG)" $(ARGS)
s2-test: soc-build
	@test "$(SOC_BOOT)" = mrom || { echo 's2-test requires SOC_BOOT=mrom'; exit 2; }
	python3 tests/m5_s2_test.py

.PHONY: soc-ref s3-test
soc-ref:
	$(MAKE) -C ../nemu -f scripts/ysyxsoc.mk
s3-test: soc-build soc-ref
	@test "$(SOC_BOOT)" = mrom || { echo 's3-test requires SOC_BOOT=mrom'; exit 2; }
	python3 tests/m5_s3_test.py

.PHONY: s4-test
s4-test: soc-ref
	$(MAKE) soc-build SOC_BOOT=mrom
	$(MAKE) soc-build SOC_BOOT=flash
	python3 tests/m5_s4_test.py

.PHONY: s5-test
s5-test: soc-ref exu-test architectural-state-test idu-contract-test
	$(MAKE) soc-build SOC_BOOT=mrom
	$(MAKE) soc-build SOC_BOOT=flash
	python3 tests/m5_s5_test.py

.PHONY: s6-build s6-test s6-delay-test
s6-build: soc-ref
	$(MAKE) soc-build SOC_BOOT=mrom SOC_DELAY=0
	$(MAKE) soc-build SOC_BOOT=flash SOC_DELAY=0
	$(MAKE) soc-build SOC_BOOT=mrom SOC_DELAY=1
	$(MAKE) soc-build SOC_BOOT=flash SOC_DELAY=1
s6-delay-test:
	mkdir -p $(NPC_HOME)/build/m5-s6/delay-unit
	verilator $(DIRECTED_TEST_FLAGS) --top-module soc_delay_channel_tb \
	 --Mdir $(NPC_HOME)/build/m5-s6/delay-unit \
	 $(NPC_HOME)/sim/soc_delay_channel.sv $(NPC_HOME)/tests/soc_delay_channel_tb.sv
	$(NPC_HOME)/build/m5-s6/delay-unit/Vsoc_delay_channel_tb +npc_delay_seed=1 +npc_delay_max=0
	$(NPC_HOME)/build/m5-s6/delay-unit/Vsoc_delay_channel_tb +npc_delay_seed=7 +npc_delay_max=7
	$(NPC_HOME)/build/m5-s6/delay-unit/Vsoc_delay_channel_tb +npc_delay_seed=1 +npc_delay_max=3 +npc_delay_fixed=1
s6-test: s6-build s6-delay-test
	python3 tests/m5_s6_test.py $(S6_ARGS)
