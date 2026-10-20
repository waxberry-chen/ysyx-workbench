# Standalone reference build: no menuconfig mutation, monitor, or auto-commit.
# Run from nemu/: make -f scripts/ysyxsoc.mk
ROOT := $(abspath .)
OUT := $(ROOT)/build/ysyxsoc
SRCS := src/cpu/cpu-exec.c src/cpu/difftest/ref.c \
 src/isa/riscv32/init.c src/isa/riscv32/inst.c src/isa/riscv32/reg.c src/isa/riscv32/logo.c \
 src/isa/riscv32/system/intr.c src/memory/vaddr.c src/memory/ysyxsoc.c \
 src/utils/log.c src/utils/state.c src/utils/timer.c src/engine/interpreter/hostcall.c
OBJS := $(patsubst %.c,$(OUT)/%.o,$(SRCS))
CFLAGS := -O2 -g -fPIC -Wall -Wextra -Wno-unused-parameter -D__GUEST_ISA__=riscv32 \
 -I$(OUT) -I$(ROOT)/include -I$(ROOT)/src/isa/riscv32/include
.DEFAULT_GOAL := all
.PHONY: all
all: $(OUT)/nemu-ref.so
$(OUT)/generated/autoconf.h: configs/ysyxsoc-ref.h
	mkdir -p $(@D)
	cp $< $@
$(OUT)/%.o: %.c $(OUT)/generated/autoconf.h
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@
$(OUT)/nemu-ref.so: $(OBJS)
	$(CC) -shared -Wl,--no-undefined $(OBJS) -o $@
-include $(OBJS:.o=.d)
