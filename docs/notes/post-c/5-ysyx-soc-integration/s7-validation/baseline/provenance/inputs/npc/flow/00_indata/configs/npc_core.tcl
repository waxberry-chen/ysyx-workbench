# 设计配置：说明“综合什么”和“希望满足什么外部条件”，不填写服务器安装路径。
# cfg 是 Tcl 字典，用 dict get cfg key 读取；末尾反斜杠把多行拼成一个命令。
# 本文件只提供数值，00_indata/constraints/core.sdc 才把数值施加到时钟/端口。
#
# top/filelist/sdc：顶层模块、按序的 SV 清单和时序约束，路径均相对 npc/。
# defines：SYNTHESIS 去掉 DPI/SVA；不更换硬件数据通路或复位行为。
# period=5 ns 是本轮 200 MHz 候选目标，不是已实现的 Fmax。
# 02 实验最差 Reg2Out 到达约 2.27 ns，加 output_max=2 ns 和 setup uncertainty=0.2 ns，
# 同一网表该路径的周期需求约 4.47 ns；5 ns 留约 0.53 ns，需重新综合/PT 验证。
# 不随频率缩短数据 I/O 预算；历史实验使用各自冻结配置。
# input/output min/max：外部接口的早/晚时序预算，不是工具测出的内部延迟。
# reset 时序暂不评估：SDC 仅对 rst_n 设置 false path，移除旧 reset_min/reset_max 假设。
# 实际复位源、脉宽和释放模型留待 SoC/reset 设计明确后填写，见 M4/reset-timing-todo.md。
# uncertainty_setup/hold：建立/保持检查分别预留的时钟裕量。
# clock/input_transition：时钟/数据边沿的变化时间（slew），不是时钟周期。
# output_load=0.01 pF：每个输出的外部电容假设，观察端口也计入。
# source_latency：时钟到达本 top 之前的延迟假设，不是尚未实现的片上时钟树延迟。
# max_cores：EDA 进程使用的主机 CPU 并行度，与 NPC 处理器核数无关。
# power_enable 默认关闭；power_toggle 为每个参考时钟周期的翻转次数，
# power_probability 为信号处于逻辑 1 的概率。它们是假设活动，不是程序波形统计。
# 数值取舍与边界见 docs/notes/post-c/4-pre-soc-signoff/2-flow.md §2。
# Design contract. Timing numbers are in ns; loads in pF after site unit review.
set cfg [dict create \
    top ysyx_core_axi4lite filelist flow/00_indata/filelists/core.f sdc flow/00_indata/constraints/core.sdc \
    defines SYNTHESIS period 5.0 input_min 0.2 input_max 2.0 \
    output_min 0.2 output_max 2.0 \
    uncertainty_setup 0.2 uncertainty_hold 0.05 clock_transition 0.1 \
    input_transition 0.1 output_load 0.01 source_latency_min 0.0 source_latency_max 0.0 \
    max_cores 4 power_enable 0 power_toggle 0.1 power_probability 0.5]
