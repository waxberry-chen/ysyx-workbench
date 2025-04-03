#Name of the module
# MODULE=keyboard_sim
# SUBMODULES=./ps2_keyboard_model.v ./ps2_keyboard.v
MODULE=ysyx_25030087_top
SUBMODULES=ysyx_25030087_IFU.v ysyx_25030087_IDU.v ysyx_25030087_EXU.v ysyx_25030087_regfile.v ysyx_25030087_alu.v ./Reg.v ./MuxKeyInternal.v ./MuxKeyWithDefault.v ./ysyx_25030087_defs.v

RANDOM_INIT=+verilator+rand+reset+2
OPTFLAGS=--x-assign unique --x-initial unique --timing

.PHONY:sim
sim: waveform.vcd

#make verilate 编译(带tb)
.PHONY:verilate
verilate: .stamp.verilate

#make build 构建可执行文件
.PHONY:build
build: obj_dir/V$(MODULE)

#make waves 生成波形并查看
.PHONY:waves
waves: waveform.vcd
	@echo
	@echo "### WAVES ###"
	gtkwave waveform.vcd

waveform.vcd: ./obj_dir/V$(MODULE)
	@echo
	@echo "### SIMULATING ###"
	@./obj_dir/V$(MODULE) $(RANDOM_INIT)

./obj_dir/V$(MODULE): .stamp.verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f V$(MODULE).mk V$(MODULE)

.stamp.verilate: $(MODULE).v tb_$(MODULE).cpp
	@echo
	@echo "### VERILATING ###"
	verilator -Wall --trace $(OPTFLAGS) -cc $(MODULE).v $(SUBMODULES) --exe tb_$(MODULE).cpp
	@touch .stamp.verilate

#detect the problems without compiling
.PHONY:lint
lint: $(MODULE).v
	verilator --lint-only $(MODULE).v

.PHONY: clean
clean:
	rm -rf .stamp.*;
	rm -rf ./obj_dir
	rm -rf waveform.vcd