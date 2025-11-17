ARGS ?= -b
IMG ?=

$(VBIN): $(CSRC) $(VSRC)
	@echo "$(COLOR_YELLOW)INFO:$(COLOR_NONE) Verilating $(VBIN)..."
	@verilator $(VFLAGS) $(CSRC) $(CINC_DIR) $(VERILOG_TOP)
	@make -s -C $(OBJ_DIR) -f $(FLAG_MK)

run: $(VBIN) $(IMG)
	@echo "$(COLOR_YELLOW)INFO-IMG:$(COLOR_NONE) $(notdir $(IMG))"
	$(VBIN) $(IMG) $(ARGS)


clean:
	@echo rm -rf OBJ_DIR *vcd
	@rm -rf $(OBJ_DIR)
	@rm -rf *.vcd