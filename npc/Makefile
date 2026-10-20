# M5 migration: only the SoC CPU interface is maintained. System harness/AM
# integration follows in S2/S3; S1 runs independent responders, not real devices.
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
	@echo 'Real ysyxSoC system build/run becomes available in S2.'
lint:
	verilator --lint-only --sv --assert -Wall -Wno-fatal --top-module ysyx_00000000 -F filelist-soc.f
build run sim:
	@echo 'S1 has independent CPU/AXI tests only. Real SoC harness arrives in S2; use make s1-test.'
	@exit 2
include scripts/tests.mk
