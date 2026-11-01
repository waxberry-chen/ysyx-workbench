# M5 S7：实际 SoC CPU wrapper，DC Ultra wire-load 综合 + pre-layout PT。
# 范围包含 core、AXI adapters/arbiter/router、内部 CLINT；不包含上游 SoC/存储模型。
# SYNTHESIS 去掉 DPI/断言；NPC_FLASH_BOOT 选择实际 Flash 启动的 PC_RST=0x30000000。
# wrapper 未连接的 commit/monitor 输出允许工具裁剪，不强制保留观察逻辑。
# 本配置独立于 M4 npc_core.tcl；两者功能/观察边界不同，不能直接比较优化收益。
# ns/pF 单位仍须由服务器 site 的库报告确认。首轮沿用 TT / 5 ns（200 MHz）预算。
# I/O 预算为同周期 SoC 边界假设，不是从完整 SoC 提取的时序；详见 soc_cpu.sdc。
# reset 为高有效，早期仅对 reset 发起路径设 false path；物理释放/脉宽仍待评估。
# power_enable 仅控制可选功耗报告，默认关闭；功耗优化由综合入口显式关闭，无功耗预算。
# DC-only 最大电容上限缩放为 0.90，参数/实现位于 02_syn/run.tcl；PT 使用原库上限。
# GShare 增量后默认显式选择模式 2；同条件 OFF 对照使用 npc_soc_cpu_bpu_off.tcl。
# max_cores 是 EDA 使用的宿主机并行度。
set cfg [dict create \
    top ysyx_25030087 filelist flow/00_indata/filelists/soc_cpu.f sdc flow/00_indata/constraints/soc_cpu.sdc \
    defines {SYNTHESIS NPC_FLASH_BOOT NPC_BPU_MODE=2} period 5.0 input_min 0.2 input_max 2.0 \
    output_min 0.2 output_max 2.0 \
    uncertainty_setup 0.2 uncertainty_hold 0.05 clock_transition 0.1 \
    input_transition 0.1 output_load 0.01 source_latency_min 0.0 source_latency_max 0.0 \
    max_cores 4 power_enable 0 power_toggle 0.1 power_probability 0.5]
