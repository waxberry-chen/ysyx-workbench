# DC-only 最大电容裕量：每个 target 库输出引脚保留原上限的 scale 部分。
# 0.90 表示收紧 10%，不是给全设计统一设置一个 pF 值，也不改变接收电容模型。
# 仅修改本 DC 进程中的 lib_pin 属性；不调用 write_lib，不修改磁盘上的工艺 DB。
# PT 在独立进程重读原始 DB，因此验收上限仍是原始库值。
# DC P-2019.03：6-18–6-19 属性设置/查询；8-4 库 DRC 可收紧；
# V-2023.12-SP5 对 lib_pin max_capacitance 的可写性/优化效果仍须服务器验证。

proc syn_capacitance_readback_matches {expected actual} {
    if {![string is double -strict $actual]} {return false}
    # 当前服务器回读呈现六位小数（单位 pF）：0.0194895 → 0.019490。
    # 固定小数位带来绝对舍入误差；单用相对容差会误拒绝较小的电容值。
    # 取半个末位单位与原相对容差的较大者，再留极小的浮点比较余量。
    set tolerance [expr {max(5.0e-7, abs($expected) * 1e-5) + 1e-12}]
    return [expr {abs($actual - $expected) <= $tolerance}]
}

proc apply_syn_max_capacitance_margin {scale} {
    global stage site reports syn_cap_limits
    if {$stage ne "syn"} {error "Capacitance margin is DC synthesis only"}
    if {![string is double -strict $scale] || !($scale > 0.0 && $scale < 1.0)} {
        error "Capacitance scale must be between 0 and 1"
    }
    if {[info exists syn_cap_limits]} {error "Capacitance margin already applied"}
    set syn_cap_limits [dict create]
    set lib [dict get $site library_name]
    # 只选本次 target 工艺库；不改 gtech、DesignWare 或其他加载的库。
    set pins [get_lib_pins -quiet ${lib}/*/* -filter {direction == out || direction == inout}]
    if {[sizeof_collection $pins] == 0} {error "No output library pins for capacitance margin: $lib"}
    redirect -file [file join $reports environment max_capacitance_margin.rpt] {
        puts "DC_ONLY_MAX_CAPACITANCE_MARGIN: library=$lib scale=$scale unit=[dict get $site capacitance_unit]"
        puts "lib_pin\toriginal_max\tsynthesis_max\treadback"
        set skipped 0
        foreach_in_collection pin $pins {
            set name [get_object_name $pin]
            # 某些 tie/特殊单元没有该限制；记录未施加对象，不凭空制造上限。
            if {[catch {get_attribute -quiet $pin max_capacitance} original] || $original eq ""} {
                puts "$name\tUNAVAILABLE\tUNCHANGED\tUNAVAILABLE"
                incr skipped
                continue
            }
            if {![string is double -strict $original] || !($original > 0.0 && $original < Inf)} {
                error "Invalid library max_capacitance: $name = $original"
            }
            set tightened [expr {$original * $scale}]
            # 原属性必须存在；不定义同名自定义属性来冒充工具约束。
            # set_attribute 的返回值不是统一的布尔状态，使用实际属性回读核验。
            set_attribute $pin max_capacitance $tightened
            set actual [get_attribute $pin max_capacitance]
            if {![syn_capacitance_readback_matches $tightened $actual]} {
                error "Capacitance margin readback mismatch: $name expected=$tightened actual=$actual"
            }
            dict set syn_cap_limits $name $tightened
            puts "$name\t$original\t$tightened\t$actual"
        }
        if {[dict size $syn_cap_limits] == 0} {error "No library max_capacitance limits were tightened"}
        puts "SUMMARY: tightened=[dict size $syn_cap_limits] without_limit=$skipped"
    }
    puts "NPC_SYN_CAP_MARGIN: scale=$scale pins=[dict size $syn_cap_limits]; DC memory only; PT uses original DB"
}

proc check_syn_max_capacitance_margin {phase} {
    global syn_cap_limits
    # 只核对已施加的策略是否保留，不实现网络 debug 查询或改变违例判定。
    dict for {name expected} $syn_cap_limits {
        set pin [get_lib_pins $name]
        set actual [get_attribute $pin max_capacitance]
        if {![syn_capacitance_readback_matches $expected $actual]} {
            error "Capacitance margin lost at $phase: $name expected=$expected actual=$actual"
        }
    }
    puts "NPC_SYN_CAP_MARGIN_CHECK: $phase pins=[dict size $syn_cap_limits]"
}
