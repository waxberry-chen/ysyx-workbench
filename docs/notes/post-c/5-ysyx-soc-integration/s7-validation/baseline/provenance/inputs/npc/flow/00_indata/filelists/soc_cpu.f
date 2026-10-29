# M5 S7 synthesis closure, paths relative to npc/. Child modules precede parents.
# ysyx_global.sv is included by the primitive; flow snapshots include files too.
# No ysyx_i_ram, harness/monitor/delay shim, generated SoC or peripheral models.
./vsrc/gnrl/ysyx_gnrl_primitive.sv
./vsrc/core/ysyx_alu.sv
./vsrc/core/ysyx_branch.sv
./vsrc/core/ysyx_gen_imm.sv
./vsrc/core/ysyx_idu.sv
./vsrc/core/ysyx_regfile.sv
./vsrc/core/ysyx_csr.sv
./vsrc/core/ysyx_ifu.sv
./vsrc/core/ysyx_opbuf.sv
./vsrc/core/ysyx_exu.sv
./vsrc/core/ysyx_lsu.sv
./vsrc/bus/ysyx_ifu_axi4_adapter.sv
./vsrc/bus/ysyx_lsu_axi4_adapter.sv
./vsrc/core/ysyx_core.sv
./vsrc/bus/ysyx_axi4_arbiter.sv
./vsrc/top/ysyx_core_axi4.sv
./vsrc/periph/ysyx_clint.sv
./vsrc/bus/ysyx_axi4_router.sv
./vsrc/top/ysyx_soc_cpu.sv
./vsrc/top/ysyx_25030087.sv
