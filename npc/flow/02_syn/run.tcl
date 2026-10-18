# DC 综合入口：冻结的 SV RTL + 工艺库 + SDC → 标准单元网表/设计数据库/报告。
# 普通非物理综合不会给出布局、时钟树或布线结果；脚本可运行也不等于时序达标。
# 组织方式参考 ref-flow 的分阶段脚本；这里将库配置移到展开/link 之前。
if {[catch {
    source [file join $::env(NPC_FLOW_SNAPSHOT) 01_common setup.tcl]
    source [file join $::env(NPC_FLOW_SNAPSHOT) 01_common capacitance.tcl]
    if {[shell_is_in_topographical_mode]} {error "Baseline requires wire-load DC, not TOPO"}
    # 阶段 1：库/工作目录准备。WORK 保存 analyze 中间数据，每个 run 独立。
    libraries
    library_reports
    define_design_lib WORK -path [file join $run work]
    # Library setup precedes analyze/elaborate/link. All sources are SV.
    # 阶段 2：analyze 检查 SV 并产生 HDL 中间表示；elaborate 根据 top、参数和
    # generate 展开层次，形成工艺无关逻辑；此时还没有完成标准单元映射。
    # current_design 指定随后命令作用的设计；link 把实例引用连接到模块/库定义。
    # 依据：DC P-2019.03 正文 6-4 / PDF 154。
    require_true [analyze -format sverilog -define [dict get $cfg defines] $rtl_sources] "analyze failed"
    elaborate $top
    current_design $top
    require_true [link] "link failed"
    # check_design 找结构问题；它不证明功能等价，也不证明所有路径满足时序。
    # redirect 将工具报告写入文件，同时保留命令返回值供 require_true 检查。
    redirect -file [file join $reports checks check_design_pre.rpt] {set ok [check_design]}
    require_true $ok "pre-compile check_design failed"
    # 阶段 3：施加环境与约束。DC 需要知道时钟和外部预算才能按目标优化。
    environment
    source [file join $npc_root [dict get $cfg sdc]]
    # 03 的无负载 EXU buffer 与 input→output 直通连接重合；本轮撤去原来的
    # set_fix_multiple_port_nets -all -buffer_constants，检验强制端口隔离是否留下冗余单元。
    # DC 默认可用 assign 表示直通/多端口网络，PT 可读该网表；module 边界不必插 buffer。
    # 依据：DC P-2019.03 正文 11-32–11-33。仍允许 compile 为真实时序/负载需求插 buffer。
    # 不手工删除 U4 等实例、不伪造内部负载，也不放宽库电容限制；结果必须由新 PT 验证。
    # 后端接入若要求修复此类连接，再单独选择重连/缓冲策略并重跑，而非提前强制补 buffer。
    puts "NPC_SYN_POLICY: no explicit multiple-port-net repair; feedthrough assigns allowed"
    # Ordinary compile avoids an implicit Ultra/Graphical/clock-gating dependency.
    # No gate_clock, scan, UPF, datapath gating, incremental or physical options.
    # 阶段 4：compile 优化逻辑并映射到 target_library 的具体单元。
    # map_effort 是映射优化努力等级，不是目标频率；目标周期由 SDC 给出。
    require_true [compile -map_effort medium] "compile failed"
    # 将层次内名字规范成 Verilog 可导出的形式，不改变要实现的逻辑功能。
    change_names -rules verilog -hierarchy
    redirect -file [file join $reports checks check_design_post.rpt] {set ok [check_design]}
    require_true $ok "post-compile check_design failed"
    # 只检查叶级单元是否仍未映射；层次容器本身不应被误当作待映射逻辑。
    # 本设计预期只有边沿触发的寄存器；发现 level-sensitive latch 则停止。
    set unmapped [get_cells -hierarchical -filter {is_hierarchical == false && is_unmapped == true}]
    if {[sizeof_collection $unmapped] != 0} {error "Unmapped cells remain"}
    if {[sizeof_collection [all_registers -level_sensitive]] != 0} {error "Unexpected latches in mapped design"}
    # 阶段 5：固定交付物。core.v 是单元实例/连线，供 PT 读取；core.ddc 是
    # DC 的设计数据库，保留工具设计信息，不能与输入的工艺 .db 混淆。
    # dc.sdc 保存 DC 当前约束作核对；PT 实际重放的是同一份原始设计 SDC。
    write -format verilog -hierarchy -output [file join $outputs core.v]
    write -format ddc -hierarchy -output [file join $outputs core.ddc]
    write_sdc [file join $outputs dc.sdc]
    # 阶段 6：报告解释。area 是映射单元面积，非 floorplan/die 面积；
    # QoR（Quality of Results）汇总优化结果；resources/reference 帮助确认
    # 乘除法等结构实际映射成了什么；design 报告用于核对环境/WLM。
    redirect -file [file join $reports area area.rpt] {report_area -hierarchy}
    redirect -file [file join $reports summary qor.rpt] {report_qor}
    redirect -file [file join $reports area resources.rpt] {report_resources -hierarchy}
    redirect -file [file join $reports area references.rpt] {report_reference -hierarchy}
    redirect -file [file join $reports environment design.rpt] {report_design}
    # TIM-134 只报告数量，不说明网络名称。按工具实际阈值查询整个层次，
    # 同时保存连接明细；不先假定它是 clk，也不修改阈值来隐藏 warning。
    # 这里数的是直接连接的 fanout，不穿透 buffer/inverter 合并整棵树。
    redirect -file [file join $reports checks high_fanout.rpt] {
        puts "high_fanout_net_threshold: [get_app_var high_fanout_net_threshold]"
        set high_fanout_nets [all_high_fanout -nets]
        puts "high_fanout_net_count: [sizeof_collection $high_fanout_nets]"
        if {[sizeof_collection $high_fanout_nets] == 0} {
            puts "No nets exceed the tool high-fanout threshold."
        } else {
            foreach_in_collection net $high_fanout_nets {
                puts "high_fanout_net: [get_object_name $net]"
                report_net -connections -verbose $net
            }
        }
    }
    # check_timing 查约束/分析完整性；constraint 列违例；report_timing 展示路径。
    # max 关注晚到数据（通常为 setup/recovery），min 关注早到数据（hold/removal）；
    # -max_paths 20 仅限制报告展示数量，不等于整个设计只分析 20 条路径。
    redirect -file [file join $reports checks check_timing.rpt] {check_timing}
    redirect -file [file join $reports checks constraint_violations.rpt] {report_constraint -all_violators -significant_digits 6 -nosplit}
    redirect -file [file join $reports timing timing_max.rpt] {report_timing -delay_type max -max_paths 20 -significant_digits 6 -nosplit}
    redirect -file [file join $reports timing timing_min.rpt] {report_timing -delay_type min -max_paths 20 -significant_digits 6 -nosplit}
    report_lsu_enable_capacitance
    # Power never changes the saved timing design. Its diagnostics are isolated.
    # 阶段 7（可选）：时序产物导出后才估算功耗，不把活动假设用于本轮优化。
    # -base_clock 将 toggle rate 关联到 core_clk 周期；时钟每周期翻转两次，
    # reset 假定不激活，其余输入只给统计活动，内部活动仍有默认/传播成分。
    # BEGIN/END 供 driver 区分可选功耗诊断；没有异常也只能标为待审查。
    # 普通 DC 的具体活动/报告选项仍须查服务器帮助；User Guide 中的 Graphical
    # 示例不是本模式已验证的依据，详见 M4/2-flow.md §6。
    set power_status "NOT_EVALUATED: disabled"
    if {[dict get $cfg power_enable]} {
        puts "NPC_OPTIONAL_POWER_BEGIN"
        set power_error [catch {
            redirect -file [file join $reports power power_attempt.rpt] {
                set_switching_activity -base_clock core_clk -toggle_rate [dict get $cfg power_toggle] \
                    -static_probability [dict get $cfg power_probability] $data_inputs
                set_switching_activity -base_clock core_clk -toggle_rate 2.0 -static_probability 0.5 [get_ports clk]
                set_switching_activity -base_clock core_clk -toggle_rate 0.0 -static_probability 1.0 [get_ports rst_n]
                report_switching_activity
                report_power
                report_power -hierarchy
            }
        } power_message]
        if {$power_error} {set power_status "NOT_EVALUATED: $power_message"} else {
            set power_status "REVIEW_REQUIRED: assumed input activity; internal default/propagated activity; no workload"
        }
        puts "NPC_OPTIONAL_POWER_END"
    }
    set f [open [file join $reports power power_status.txt] w]; puts $f $power_status; close $f
    complete
} message]} {puts stderr "NPC_FLOW_ERROR: $message"; exit 1}
exit 0
