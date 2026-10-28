# M5: real SoC harness, AM runtime and per-commit DiffTest.
# S1 retains independent responder checks alongside real-system tests.
.DEFAULT_GOAL := help
NPC_HOME := $(abspath .)
VSRC_DIR := $(NPC_HOME)/vsrc/core
OBJ_DIR := $(NPC_HOME)/build/m5-s1
NPC_PLATFORM ?= ysyxsoc
ifneq ($(NPC_PLATFORM),ysyxsoc)
$(error legacy/B1 retired in M5 S1; reproduce them with the M4/S0 Git revision)
endif
.PHONY: help lint build run sim
help:
	@echo 'M5 S1: make s1-test; make lint; artifacts: npc/build/m5-s1'
	@echo 'M5 S2: make s2-test; make run IMG=/path/to/mrom.bin [ARGS="..."]'
	@echo 'M5 S3: make s3-test; AM ARCH=riscv32e-ysyxsoc; make soc-ref'
	@echo 'M5 S4: make s4-test; make run SOC_BOOT=flash IMG=/path/to/flash.bin'
	@echo 'M5 S5: make s5-test; timer IRQ, AM context and RT-Thread tick'
	@echo 'M5 S6: make s6-test; preemption/wakeup, stack/heap, serial UART and system regression'
lint:
	verilator --lint-only --sv --assert -Wall -Wno-fatal --top-module ysyx_25030087 -F filelist-soc.f
include scripts/tests.mk
include scripts/soc.mk
