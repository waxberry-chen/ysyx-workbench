# M5 S7 的 CPU 子系统边界约束，DC/PT 重放同一份冻结输入。
# clock/reset 是真实 wrapper 端口：reset 高有效，wrapper 内反相为 rst_n。
# SoC 的 reset 延长逻辑在本 scope 外，不能把其仿真周期当作物理复位保证。
create_clock -name core_clk -period [dict get $cfg period] [get_ports clock]
set_clock_uncertainty -setup [dict get $cfg uncertainty_setup] [get_clocks core_clk]
set_clock_uncertainty -hold [dict get $cfg uncertainty_hold] [get_clocks core_clk]
set_clock_transition [dict get $cfg clock_transition] [get_clocks core_clk]
set_clock_latency -source -min [dict get $cfg source_latency_min] [get_clocks core_clk]
set_clock_latency -source -max [dict get $cfg source_latency_max] [get_clocks core_clk]

# 本配置关闭外部 IRQ/ChipLink，CPU slave 无访问源。这些端口仅用于 ABI/仿真断言，
# 不是内部 CLINT timer_irq；绝不能将内部 timer_irq 或正常 AXI master 响应常量化。
# 明确列出输入端口，避免 io_slave_* 把输出一起选中，或未来新接口被自动豁免。
set inactive_inputs [get_ports {io_interrupt \
    io_slave_awvalid io_slave_awaddr io_slave_awid io_slave_awlen io_slave_awsize io_slave_awburst \
    io_slave_wvalid io_slave_wdata io_slave_wstrb io_slave_wlast io_slave_bready \
    io_slave_arvalid io_slave_araddr io_slave_arid io_slave_arlen io_slave_arsize io_slave_arburst \
    io_slave_rready}]
set_case_analysis 0 $inactive_inputs

# 活动输入：SoC 对 CPU AXI master 的 READY/读响应/写响应。
# min/max=0.2/2.0 ns 是外部发起端的早/晚到达预算，参考同一 core_clk。
# RID/BID/RLAST 在当前单拍合同中还承担仿真协议检查；综合后可能不形成数据路径，
# 仍完整保留端口预算，具体无路径原因须核对网表/check_timing/coverage。
set data_inputs [get_ports {io_master_awready io_master_wready \
    io_master_bvalid io_master_bresp io_master_bid io_master_arready \
    io_master_rvalid io_master_rresp io_master_rdata io_master_rlast io_master_rid}]
set_input_delay -clock core_clk -min [dict get $cfg input_min] $data_inputs
set_input_delay -clock core_clk -max [dict get $cfg input_max] $data_inputs

# 仅延后 reset 发起的 recovery/removal、reset→数据/输出路径；不排除内部 timer 数据。
# 不对 reset 做 case analysis，不关闭库电气检查，也不假设物理脉宽已经满足。
# 以后确定 reset 源、同步释放和实际输入时序后，重新建立复位时序约束。
set_false_path -from [get_ports reset]
set_input_transition [dict get $cfg input_transition] [remove_from_collection [all_inputs] [get_ports clock]]

# 所有输出施加相同接收预算与 10 fF 外部负载，包含 AXI 控制/数据及常量 tie-off。
# 常量输出没有普通数据时序路径是预期行为，不能据此豁免活动端口。
# output -min=+0.2 ns 是现有比较假设，不表示外部接收端 hold 要求为 +0.2 ns。
set_output_delay -clock core_clk -min [dict get $cfg output_min] [all_outputs]
set_output_delay -clock core_clk -max [dict get $cfg output_max] [all_outputs]
set_load [dict get $cfg output_load] [all_outputs]
# 时钟保持 ideal；DC-only max_fanout=32 和 clock DRC 保护在 02_syn/run.tcl 中执行。
# 无 multicycle、generated clock、SPEF 或 reset 常量化；WLM 由同一 site 配置控制。
