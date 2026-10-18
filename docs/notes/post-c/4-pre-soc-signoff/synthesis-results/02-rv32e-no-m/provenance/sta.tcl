# PT 静态时序入口：同一 run 的映射网表 + 同一工艺库 + 同一设计 SDC。
# 本轮是 pre-layout、单角、ideal-clock 基线；不是布局布线后的 sign-off。
# library/units/WLM 报告用于核对模型，timing/coverage 用于核对路径及检查是否完整。
if {[catch {
    source [file join $::env(NPC_FLOW_SNAPSHOT) 01_common setup.tcl]
    libraries
    library_reports
    # 阶段 1：只读本 run 的综合网表。PT 根据库中的单元时序模型构建分析图，
    # 不执行程序、不需要 testbench，也不在这里重新综合或替换逻辑。
    read_verilog [file join $outputs core.v]
    require_true [link_design $top] "PT link_design failed"
    environment
    # Replay the same frozen design SDC, not DC-specific exported environment commands.
    # dc.sdc is still retained and hashed for cross-checking; no C906 SDC is used.
    source [file join $npc_root [dict get $cfg sdc]]
    # 阶段 2：在网表/库/约束齐备后更新时序图，计算 arrival/required time 和 slack。
    # arrival time 是信号预计到达时间，required time 是约束要求的到达边界。
    # setup 要求数据在捕获时钟沿之前足够早地稳定；hold 要求沿之后继续保持一段时间。
    # 晚到检查的 slack 通常是 required - arrival，早到检查则是 arrival - required；
    # 两者均以负值表示违例，所以“数据越快越好”并不适用于 hold 检查。
    # 无 SPEF，且未传播时钟树；数据路径仍使用单元延迟及配置的互连估算。
    update_timing
    redirect -file [file join $reports units.rpt] {report_units}
    redirect -file [file join $reports design.rpt] {report_design}
    redirect -file [file join $reports wire_load.rpt] {report_wire_load}
    # 阶段 3：先确认“分析了什么”，再看“是否满足目标”。
    # coverage 的 met/violated/untested 分别是通过、违例、未测试的 timing checks。
    # untested 不可当作通过；常量、例外、无时钟等原因需要逐项解释。
    # 该 coverage 不是 RTL 仿真覆盖率。依据：PT L-2016.06 正文 17-25 / PDF 657。
    redirect -file [file join $reports check_timing.rpt] {check_timing -verbose}
    redirect -file [file join $reports coverage.rpt] {report_analysis_coverage}
    redirect -file [file join $reports coverage_untested.rpt] {report_analysis_coverage -status_details {untested}}
    redirect -file [file join $reports constraints.rpt] {report_constraint -all_violators -nosplit}
    # 阶段 4：max/min 分别保存晚到/早到分析；全局报告包含实际可分析的 check。
    # 先输出代表路径供人阅读，再独立提取全部负 slack 端点，避免只用前 20 条算 TNS。
    foreach delay {max min} {
        redirect -file [file join $reports timing_${delay}.rpt] {report_timing -delay_type $delay -max_paths 20 -nosplit}
        # One worst path per endpoint; bounded to a count above all pins + ports.
        set limit [expr {[sizeof_collection [get_pins -hierarchical *]] + [sizeof_collection [all_outputs]] + 1}]
        set paths [get_timing_paths -delay_type $delay -slack_lesser_than 0.0 -nworst 1 -max_paths $limit]
        if {[sizeof_collection $paths] >= $limit} {error "Timing path enumeration may be truncated"}
        # 同一 endpoint 可能在返回路径中重复出现，只保留该端点最坏的 slack，
        # 否则 TNS 和 violating_endpoints 会重复计数。
        set endpoints [dict create]
        foreach_in_collection path $paths {
            set slack [get_attribute $path slack]
            set endpoint [get_object_name [get_attribute $path endpoint]]
            if {![dict exists $endpoints $endpoint] || $slack < [dict get $endpoints $endpoint]} {
                dict set endpoints $endpoint $slack
            }
        }
        # WNS（Worst Negative Slack）= 最坏负裕量；无违例时这里取 0。
        # TNS（Total Negative Slack）= 每个违例端点最坏负裕量之和。
        # 正裕量不会抵消负裕量；WNS=0 也不证明所有功能端点均已受约束。
        set tns 0.0; set wns 0.0; set count 0
        dict for {endpoint slack} $endpoints {
            set tns [expr {$tns + $slack}]
            set wns [expr {min($wns, $slack)}]
            incr count
        }
        set f [open [file join $reports metrics_${delay}.tsv] w]
        puts $f "wns\t$wns\ntns\t$tns\nviolating_endpoints\t$count"
        close $f
        # 阶段 5：按边界保存四类路径，方便定位是内部逻辑还是接口预算限制频率。
        # Reg2Reg：寄存器→寄存器；In2Reg：输入→寄存器；
        # Reg2Out：寄存器→输出；In2Out：组合穿越（含 monitor 观察路径）。
        # -clock_pins 指发起数据的寄存器时钟引脚，不是只分析时钟树。
        # -data_pins 限定寄存器数据端，故这四类报告不能替代全局 recovery/removal
        # coverage；reset release 检查仍要在全局时序/coverage 报告里审查。
        set external_inputs [remove_from_collection [all_inputs] [get_ports clk]]
        foreach {group from to} [list Reg2Reg [all_registers -clock_pins] [all_registers -data_pins] \
                In2Reg $external_inputs [all_registers -data_pins] \
                Reg2Out [all_registers -clock_pins] [all_outputs] In2Out $external_inputs [all_outputs]] {
            redirect -file [file join $reports ${group}_${delay}.rpt] {
                report_timing -from $from -to $to -delay_type $delay -max_paths 10 -nosplit
            }
        }
    }
    complete
} message]} {puts stderr "NPC_FLOW_ERROR: $message"; exit 1}
exit 0
