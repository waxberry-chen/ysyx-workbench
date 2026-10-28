# Real SoC simulation. The peripheral models are already instantiated by Full.
SOC_HOME := $(abspath ../ysyxSoC)
SOC_BOOT ?= mrom
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
SOC_RTL := $(SOC_HOME)/build/ysyxSoCFull.v
SOC_BINARY := $(SOC_BUILD)/VysyxSoCFull
SOC_PERIPH := $(shell rg --files $(SOC_HOME)/perip -g '*.v' | sort)
SOC_FLAGS := --cc --exe --build -j 2 --sv --timing --assert --trace-fst \
 --timescale-override 1ns/1ps -Wall -Wno-fatal -Wno-SYNCASYNCNET \
 -Werror-WIDTH -Werror-PINMISSING -Werror-PINNOTFOUND -Werror-LATCH \
 -Werror-UNOPTFLAT -Werror-UNDRIVEN --top-module ysyxSoCFull \
 -I$(SOC_HOME)/perip/uart16550/rtl -I$(SOC_HOME)/perip/spi/rtl \
 -F filelist-soc.f $(SOC_RTL) $(SOC_PERIPH) $(NPC_HOME)/sim/soc_monitor.sv \
 $(NPC_HOME)/csrc/soc/main.cpp $(NPC_HOME)/csrc/soc/difftest.cpp \
 $(SOC_BOOT_FLAGS) -CFLAGS '-std=c++17 -Wall -Wextra $(SOC_BOOT_FLAGS)' -LDFLAGS '-ldl' --Mdir $(SOC_BUILD)
.PHONY: soc-verilog soc-build build run sim s2-test
soc-verilog:
	$(MAKE) -C $(SOC_HOME) verilog
soc-build: soc-verilog
	mkdir -p $(SOC_BUILD)
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
