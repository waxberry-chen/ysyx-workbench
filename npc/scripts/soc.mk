# Real SoC simulation. The peripheral models are already instantiated by Full.
SOC_HOME := $(abspath ../ysyxSoC)
SOC_BUILD := $(NPC_HOME)/build/ysyxsoc
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
 -CFLAGS '-std=c++17 -Wall -Wextra' -LDFLAGS '-ldl' --Mdir $(SOC_BUILD)
.PHONY: soc-verilog soc-build build run sim s2-test
soc-verilog:
	$(MAKE) -C $(SOC_HOME) verilog
soc-build: soc-verilog
	mkdir -p $(SOC_BUILD)
	verilator $(SOC_FLAGS)
build: soc-build
# Supply a raw MROM image (<=4 KiB). The harness never preloads SRAM.
run sim: soc-build
	@test -n "$(IMG)" || { echo 'Use make -C npc run IMG=/path/to/mrom.bin [ARGS="..."]'; exit 2; }
	$(SOC_BINARY) --mrom "$(IMG)" $(ARGS)
s2-test: soc-build
	python3 tests/m5_s2_test.py

.PHONY: soc-ref s3-test
soc-ref:
	$(MAKE) -C ../nemu -f scripts/ysyxsoc.mk
s3-test: soc-build soc-ref
	python3 tests/m5_s3_test.py
