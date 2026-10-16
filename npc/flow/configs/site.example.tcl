# 服务器配置示例：复制为 site.local.tcl 后填写，避免把机器配置混入设计约束。
# .db 是编译后的逻辑工艺库，提供标准单元的功能、面积、时序/功耗模型；
# 它不是 NPC 的设计网表，也不是布局布线后的寄生参数文件。
# PVT = Process / Voltage / Temperature（工艺角/电压/温度）；Vt 是单元阈值电压类别。
# 此处只选一个 RVT/TT 候选；文件名给出线索，但必须以 probe 输出的库内容为准。
# library_name 是工具读入后的库内部名称，不保证等于文件名；operating_condition
# 必须是该库真实定义的工作条件。留空可执行 probe，但会阻止正式综合。
# library_reviewed=1 是用户核对库报告后的声明，Python 并不会自行解析二进制 DB 验证单位。
# time/capacitance_unit 必须匹配 SDC 的 ns/pF；area_unit 不能未经依据改写成 um^2。
# wire_load_model 选择互连估算策略；具体含义与优先级见 common/setup.tcl。
# 参考路径来自 ref-flow/03_scr/env/auto.tcl；无需为了本地检查把库搬到本机。
# Copy to site.local.tcl on the server. Paths retained from ref-flow auto.tcl.
# One RVT/TT candidate, not the original mixed RVT/LVT/HVT + SRAM glob.
set site [dict create \
    dc_shell /15T/tools/synopsys/syn/O-2018.06-SP1/bin/dc_shell \
    pt_shell pt_shell \
    target_db /15T/Projects/c906-project-delivery/00_indata/DB/STD_NEW/tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs.db \
    library_name tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs \
    operating_condition {} corner TT_0p9V_25C vt RVT \
    time_unit ns capacitance_unit pf area_unit library_area \
    wire_load_model library_default library_reviewed 0]
# First run `make probe SITE=... RUN_ID=lib-probe` to inspect report_lib.
# Then set actual library_name/operating_condition, verify units and PVT/Vt,
# record area_unit (do not assume um^2), and set library_reviewed=1.
# wire_load_model: library_default (explicit policy, auto selection disabled),
# or an exact named model present in this library; same policy in DC and PT.
# Optional DC power is off by default; enable only after command/model review.
