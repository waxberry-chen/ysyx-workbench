################################
#     Main Makefile of npc     #
################################
NPC_PLATFORM ?= legacy
SRAM_BYTES ?= 1048576
MTIME_HZ ?= 1000000
B1_SIM_SHIM ?= 0
ifeq ($(NPC_PLATFORM),b1)
TOP_MODULE := ysyx_b1_top
RTL_LIST := filelist-b1.f
PLATFORM_CFLAGS := -DNPC_B1 -DNPC_SRAM_BYTES=$(SRAM_BYTES) -DNPC_MTIME_HZ=$(MTIME_HZ)
PLATFORM_VFLAGS := -GSRAM_BYTES=$(SRAM_BYTES)
ifeq ($(B1_SIM_SHIM),1)
PLATFORM_CFLAGS += -DNPC_B1_SHIM
PLATFORM_VFLAGS += -DB1_SIM_SHIM $(abspath tests/axi4lite_delay_shim.sv)
endif
else ifeq ($(NPC_PLATFORM),legacy)
TOP_MODULE := ysyx_core
RTL_LIST := filelist.f
else
$(error NPC_PLATFORM must be legacy or b1)
endif
LINT_TOP	?= $(TOP_MODULE)

NPC_HOME	:= $(abspath .)
OBJ_DIR := $(abspath ./build$(if $(filter b1,$(NPC_PLATFORM)),/b1-$(SRAM_BYTES)-$(MTIME_HZ)))
ifeq ($(B1_SIM_SHIM),1)
ifneq ($(NPC_PLATFORM),b1)
$(error B1_SIM_SHIM=1 requires NPC_PLATFORM=b1)
endif
OBJ_DIR := $(OBJ_DIR)-shim
endif
CSRC_DIR 	:= $(abspath ./csrc)
VSRC_DIR	:= $(abspath ./vsrc/core)
REWRITE_MK 	:= $(abspath ./scripts/rewrite.mk)
VSRC_PATH	:= $(abspath ./$(RTL_LIST))

VERILOG_TOP := $(VSRC_DIR)/$(TOP_MODULE).v
VBIN		:= $(OBJ_DIR)/$(addprefix V, $(basename $(notdir $(VERILOG_TOP)))) 	# generate VBIN

CINC_DIR 	:= -CFLAGS -I$(CSRC_DIR)/include -I$(NEMU_HOME)/tools/capstone/repo/include
CSRC 		:= $(shell find $(CSRC_DIR) -name "*.c*")
ifeq ($(NPC_PLATFORM),b1)
CSRC := $(filter-out $(CSRC_DIR)/memory/ram_model.cpp $(CSRC_DIR)/memory/map.c \
  $(CSRC_DIR)/memory/mmio.c $(wildcard $(CSRC_DIR)/periph/*.c),$(CSRC))
endif
CHEADERS	:= $(shell find $(CSRC_DIR) -name "*.h")
# filelist.f is currently a source-only list.  Expand it so RTL edits are real
# prerequisites of the Verilator binary instead of relying on `make clean`.
VSRC		:= $(abspath $(shell sed -e '/^[[:space:]]*\#/d' -e '/^[[:space:]]*$$/d' $(VSRC_PATH)))
ifeq ($(B1_SIM_SHIM),1)
VSRC += $(abspath tests/axi4lite_delay_shim.sv)
endif

### Difftest ###
# NEMUISO 	:= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so

### Verilator Flags ###
VFLAGS = $(PLATFORM_VFLAGS) -CFLAGS "$(PLATFORM_CFLAGS)" --trace --cc -stats --exe --assert -O3 --threads-dpi all \
						-F $(VSRC_PATH) \
						-Mdir $(OBJ_DIR) \
						-DDIFF \
						-DNPC_SIM_DPI \
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

.PHONY: all sim
all: run
	@echo "'all' target equals to 'run'"

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!

COLOR_RED   		= \033[1;31m
COLOR_GREEN 		= \033[1;32m
COLOR_YELLOW 		= \033[33m
COLOR_NONE  		= \033[0m

include ./scripts/build.mk
include ./scripts/tests.mk
