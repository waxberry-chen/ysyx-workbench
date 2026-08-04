ARGS ?= 
IMG ?= $(NPC_HOME)/dummy-riscv32e-npc.bin

VFLAGS += --trace-fst

$(VBIN): $(CSRC) $(VSRC)
	@echo "$(COLOR_YELLOW)INFO:$(COLOR_NONE) Verilating $(VBIN)..."
	@verilator $(VFLAGS) $(CSRC) $(CINC_DIR)
	@make -s -C $(OBJ_DIR) -f $(REWRITE_MK)

run: $(VBIN) $(IMG)
	@echo "$(COLOR_YELLOW)load_img:$(COLOR_NONE) $(notdir $(IMG))"
	$(VBIN) $(IMG) $(ARGS)

gdb: $(VBIN) $(ILM_IMG) $(DLM_IMG)
	@echo "$(COLOR_YELLOW)load_img:$(COLOR_NONE) $(ILM_IMG) $(DLM_IMG)"
	@gdb -s $(VBIN) --args $(VBIN) $(IMG) $(ARGS)

clean:
	@echo rm -rf OBJ_DIR *vcd
	@rm -rf $(OBJ_DIR)
	@rm -rf *.vcd