################################
#     Main Makefile of npc     #
################################
TOP_MODULE 	:= ysyx_core
RTL_LIST	:= filelist.f
LINT_TOP	?= $(TOP_MODULE)
RAM_SEEDS	?= 1 2 3 4 5 6 7 8 9 10
RAM_MAX_LATENCY ?= 7
RAM_READY_PERCENT ?= 50

NPC_HOME	:= $(abspath .)
OBJ_DIR		:= $(abspath ./build)
CSRC_DIR 	:= $(abspath ./csrc)
VSRC_DIR	:= $(abspath ./vsrc/core)
REWRITE_MK 	:= $(abspath ./scripts/rewrite.mk)
VSRC_PATH	:= $(abspath ./$(RTL_LIST))

VERILOG_TOP := $(VSRC_DIR)/$(TOP_MODULE).v
VBIN		:= $(OBJ_DIR)/$(addprefix V, $(basename $(notdir $(VERILOG_TOP)))) 	# generate VBIN

CINC_DIR 	:= -CFLAGS -I$(CSRC_DIR)/include -I$(NEMU_HOME)/tools/capstone/repo/include
CSRC 		:= $(shell find $(CSRC_DIR) -name "*.c*")
CHEADERS	:= $(shell find $(CSRC_DIR) -name "*.h")
# filelist.f is currently a source-only list.  Expand it so RTL edits are real
# prerequisites of the Verilator binary instead of relying on `make clean`.
VSRC		:= $(abspath $(shell sed -e '/^[[:space:]]*\#/d' -e '/^[[:space:]]*$$/d' $(VSRC_PATH)))

### Difftest ###
# NEMUISO 	:= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so

### Verilator Flags ###
VFLAGS 				= --trace --cc -stats --exe -O3 --threads-dpi all \
						-F $(VSRC_PATH) \
						-Mdir $(OBJ_DIR) \
						-DDIFF \
						--no-timing \
						--top-module $(TOP_MODULE) \
						-Wno-fatal \
						-Wno-REDEFMACRO \
						--timescale-override "1ns/1ps"

LINT_FLAGS			= --lint-only --sv -Wall -Wno-fatal \
						-F $(VSRC_PATH) \
						--top-module $(LINT_TOP)

# Usage: make lint [LINT_TOP=<module>]
.PHONY: lint
lint:
	verilator $(LINT_FLAGS)

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

all: run
	@echo "'all' target equals to 'run'"

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!

COLOR_RED   		= \033[1;31m
COLOR_GREEN 		= \033[1;32m
COLOR_YELLOW 		= \033[33m
COLOR_NONE  		= \033[0m

include ./scripts/build.mk
