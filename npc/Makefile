#################
#     Paths     #
#################
OBJ_DIR		:= $(abspath ./build)
CSRC_DIR 	:= $(abspath ./csrc)
VSRC_DIR	:= $(abspath ./vsrc/core)
FLAG_MK 	:= $(abspath ./scripts/flags.mk)

VERILOG_TOP := $(VSRC_DIR)/CPU.v
NEMUISO 	:= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
VFLAGS		:= --trace --cc --exe -O3 --threads-dpi all -I$(VSRC_DIR) -Mdir $(OBJ_DIR) -DDIFF
VSRC		:= $(shell find $(VSRC_DIR) -name "*.v")
VBIN		:= $(OBJ_DIR)/$(addprefix V, $(basename $(notdir $(VERILOG_TOP)))) 	# build/VCPU

CINC_DIR 	:= -CFLAGS -I$(CSRC_DIR)/include
CSRC 		:= $(shell find $(CSRC_DIR) -name "*.c*")

all: run
	@echo "'all' target equals to 'run'"

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "Write this Makefile by your self."



#########################
#     Miscellaneous     #
#########################
COLOR_RED   		= \033[1;31m
COLOR_GREEN 		= \033[1;32m
COLOR_YELLOW 		= \033[33m
COLOR_NONE  		= \033[0m

include ./scripts/build.mk
include ../Makefile
