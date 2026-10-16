# SDC（Synopsys Design Constraints）规定分析边界；不是描述硬件连接的 RTL。
# 此文件由 DC/PT 在设计已 link 后 source，cfg 来自运行快照，不在此处改配置值。
# Shared by DC and PT. Never case-analyze reset for timing: retain recovery/removal.
# cfg is frozen by the launcher; reviewed library units are ns and pF.
# 1. 创建逻辑时钟对象：clk 是 RTL 端口，core_clk 是 STA 中使用的时钟名。
# period 规定每个周期预算；本例 10 ns 仅是试探目标。
create_clock -name core_clk -period [dict get $cfg period] [get_ports clk]
# 2. uncertainty 为建立/保持检查预留裕量；transition 是边沿变化时间。
# 两者都不是为时钟增加一个周期，也不是实测的时钟树延迟。
set_clock_uncertainty -setup [dict get $cfg uncertainty_setup] [get_clocks core_clk]
set_clock_uncertainty -hold [dict get $cfg uncertainty_hold] [get_clocks core_clk]
set_clock_transition [dict get $cfg clock_transition] [get_clocks core_clk]
# source latency 描述时钟到达当前 top 之前的早/晚延迟；本例都为零。
# ideal clock 仅简化时钟网络传播，不会把数据路径的门延迟也设成零。
set_clock_latency -source -min [dict get $cfg source_latency_min] [get_clocks core_clk]
set_clock_latency -source -max [dict get $cfg source_latency_max] [get_clocks core_clk]
# 3. Input delay：外部发起端到当前输入端口的早/晚到达预算，相对 core_clk。
# max 参与 setup 等晚到检查，min 参与 hold 等早到检查；不能只给 max。
# clk 不当作普通数据输入；rst_n 分开写，便于审查复位释放假设。
# all_inputs/get_ports 返回工具 collection；remove_from_collection 做对象差集。
set data_inputs [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay -clock core_clk -min [dict get $cfg input_min] $data_inputs
set_input_delay -clock core_clk -max [dict get $cfg input_max] $data_inputs
# External reset release is assumed synchronous. Assertion is asynchronous.
# 异步复位的“释放”仍需避开时钟采样窗口（recovery/removal 类似 setup/hold）。
# 输入 delay 描述外部同步释放假设，不会在 RTL 中自动插入 reset synchronizer。
# 不把 reset 整体设 false path，也不通过 case analysis 抹掉其时序路径。
set_input_delay -clock core_clk -min [dict get $cfg reset_min] [get_ports rst_n]
set_input_delay -clock core_clk -max [dict get $cfg reset_max] [get_ports rst_n]
# 数据/reset 输入使用指定 slew 代替猜测一个外部 driving cell；clock 的 slew 单独设置。
set_input_transition [dict get $cfg input_transition] [remove_from_collection [all_inputs] [get_ports clk]]
# 4. Output delay：当前输出之后留给外部接收端的时序预算，不是本模块的门延迟。
# max 通常包含外部连线延迟和接收端 setup；min 按 SDC 的 hold 符号约定填写。
# 在零外部线延迟的简化场景中，接收端要求正 hold H 时常用 output -min = -H；
# 因此本例 +0.2 ns 不能读成“接收端要求 0.2 ns hold”，它只是当前接口假设。
# 端口延迟语义见 PT L-2016.06 正文 5-3–5-5 / PDF 147–149。
# all_outputs 包括 commit/monitor；否则可能得到乐观而不可比的面积/时序结果。
set_output_delay -clock core_clk -min [dict get $cfg output_min] [all_outputs]
set_output_delay -clock core_clk -max [dict get $cfg output_max] [all_outputs]
# 外部负载电容会影响驱动单元延迟与尺寸选择；0.01 pF = 10 fF，需先确认库单位。
set_load [dict get $cfg output_load] [all_outputs]
# Clocks remain ideal; no false/multicycle paths, SPEF or propagated clocks.
