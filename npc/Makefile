################################
#     Main Makefile of npc     #
################################
TOP_MODULE 	:= ysyx_core
RTL_LIST	:= filelist.f

NPC_HOME	:= $(abspath .)
OBJ_DIR		:= $(abspath ./build)
CSRC_DIR 	:= $(abspath ./csrc)
VSRC_DIR	:= $(abspath ./vsrc/core)
REWRITE_MK 	:= $(abspath ./scripts/rewrite.mk)

VERILOG_TOP := $(VSRC_DIR)/$(TOP_MODULE).v
VBIN		:= $(OBJ_DIR)/$(addprefix V, $(basename $(notdir $(VERILOG_TOP)))) 	# generate VBIN
VSRC_PATH	:= $(abspath ./$(RTL_LIST))

CINC_DIR 	:= -CFLAGS -I$(CSRC_DIR)/include -I$(NEMU_HOME)/tools/capstone/repo/include
CSRC 		:= $(shell find $(CSRC_DIR) -name "*.c*")

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

all: run
	@echo "'all' target equals to 'run'"

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!

COLOR_RED   		= \033[1;31m
COLOR_GREEN 		= \033[1;32m
COLOR_YELLOW 		= \033[33m
COLOR_NONE  		= \033[0m

include ./scripts/build.mk
