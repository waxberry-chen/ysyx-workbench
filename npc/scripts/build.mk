ARGS ?= -d $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
IMG ?= $(NPC_HOME)/dummy-riscv32e-npc.bin

VFLAGS += --trace-fst

$(VBIN): $(CSRC) $(VSRC)
	@echo "$(COLOR_YELLOW)INFO:$(COLOR_NONE) Verilating $(VBIN)..."
	@verilator $(VFLAGS) $(CSRC) $(CINC_DIR)
	@make -s -C $(OBJ_DIR) -f $(REWRITE_MK)

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