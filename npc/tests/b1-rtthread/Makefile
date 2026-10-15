NAME := b1-rtthread
RTT := $(abspath ../../../rt-thread-am)
SRCS := workload.c $(RTT)/bsp/abstract-machine/src/context.c
SRCS += $(addprefix $(RTT)/src/,clock.c idle.c irq.c kservice.c mem.c object.c scheduler_up.c thread.c timer.c)
INC_PATH += $(RTT)/include
CFLAGS += -D__RTTHREAD__ -Wno-nonnull-compare
include $(AM_HOME)/Makefile
