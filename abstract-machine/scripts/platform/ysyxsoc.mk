AM_SRCS := riscv/ysyxsoc/start.S riscv/ysyxsoc/trm.c riscv/ysyxsoc/ioe.c \
           riscv/npc/cte.c riscv/npc/trap.S \
           platform/dummy/vme.c platform/dummy/mpe.c
CFLAGS += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/ysyxsoc.ld
ifneq ($(SOC_BOOT),mrom)
AM_SRCS := $(subst riscv/ysyxsoc/start.S,riscv/ysyxsoc/flash-start.S,$(AM_SRCS))
LDSCRIPTS := $(AM_HOME)/scripts/ysyxsoc-$(SOC_BOOT).ld
endif
LDFLAGS += --gc-sections -e _start -Map=$(IMAGE).map

MAINARGS_MAX_LEN = 64
MAINARGS_PLACEHOLDER = The insert-arg rule in Makefile will insert mainargs here.
CFLAGS += -DMAINARGS_MAX_LEN=$(MAINARGS_MAX_LEN) -DMAINARGS_PLACEHOLDER=\""$(MAINARGS_PLACEHOLDER)"\"

image: image-dep
	@$(OBJDUMP) -d $(IMAGE).elf > $(IMAGE).txt
	@$(OBJCOPY) -S -O binary $(IMAGE).elf $(IMAGE).bin

.PHONY: insert-arg
insert-arg: image
	@python3 $(AM_HOME)/tools/insert-arg.py $(IMAGE).bin $(MAINARGS_MAX_LEN) "$(MAINARGS_PLACEHOLDER)" "$(mainargs)"

# The reference profile is isolated from NEMU's normal .config and build.
run: insert-arg
	$(MAKE) -C $(NPC_HOME) soc-ref SOC_BOOT=mrom
	$(MAKE) -C $(NPC_HOME) run SOC_BOOT=$(if $(filter mrom,$(SOC_BOOT)),mrom,flash) IMG=$(IMAGE).bin \
	  ARGS="--diff $(NPC_HOME)/../nemu/build/ysyxsoc/nemu-ref.so $(ARGS)"
