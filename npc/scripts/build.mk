ARGS ?= -d $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
IMG ?= $(NPC_HOME)/dummy-riscv32e-npc.bin

VFLAGS += --trace-fst

BUILD_CONFIG := $(OBJ_DIR)/npc-build-config
.PHONY: build-config-force
$(BUILD_CONFIG): build-config-force
	@mkdir -p $(OBJ_DIR)
	@printf '%s\n' '$(NPC_PLATFORM) $(SRAM_BYTES) $(MTIME_HZ) $(VFLAGS)' > $@.tmp
	@cmp -s $@.tmp $@ || cp $@.tmp $@

$(VBIN): $(BUILD_CONFIG) $(NPC_HOME)/Makefile $(wildcard $(NPC_HOME)/scripts/*.mk) $(CSRC) $(CHEADERS) $(VSRC) $(VSRC_PATH)
	@echo "$(COLOR_YELLOW)INFO:$(COLOR_NONE) Verilating $(VBIN)..."
	@verilator $(VFLAGS) $(CSRC) $(CINC_DIR)
	@make -s -C $(OBJ_DIR) -f $(REWRITE_MK) VTOP=$(notdir $(VBIN))

# here should put $(IMG) at last 
run: $(VBIN) $(IMG)
	@echo "$(COLOR_YELLOW)load_img:$(COLOR_NONE) $(notdir $(IMG))"
	$(VBIN) $(ARGS) $(IMG)

gdb: $(VBIN) $(ILM_IMG) $(DLM_IMG)
	@echo "$(COLOR_YELLOW)load_img:$(COLOR_NONE) $(ILM_IMG) $(DLM_IMG)"
	@gdb -s $(VBIN) --args $(VBIN) $(ARGS) $(IMG)

clean:
	@echo rm -rf OBJ_DIR *vcd/fst
	@rm -rf $(OBJ_DIR)
	@rm -rf *.vcd
	@rm -rf *.fst

.PHONY: build
build: $(VBIN)
