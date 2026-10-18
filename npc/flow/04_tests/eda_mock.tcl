# 本文件供本地测试使用，不能作为 DC/PT 替代品或服务器执行入口。
# source 的是实际 syn/sta 脚本；仅在当前解释器提供明确的假 EDA 命令，检查 Tcl 控制流。
# 两条假路径故意使用同一 endpoint，检验 TNS 去重；功耗命令故意报错，检验可选失败隔离。
# MOCK 面积/时序数字仅是解析器测试数据，不能引用为 NPC 的实现结果。
# Explicit mock command surface for executing the real Tcl control flow locally.
# It tests Tcl wiring/ordering only. No library semantics, synthesis or STA.
set search_path {}
set mock_channel stdout
rename puts mock_real_puts
proc puts {args} {
    if {[llength $args] == 1 && $::mock_channel ne "stdout"} {
        mock_real_puts $::mock_channel [lindex $args 0]
    } else {mock_real_puts {*}$args}
}
proc redirect {flag path body} {
    if {$flag ne "-file"} {error "Mock only supports -file"}
    set previous $::mock_channel
    set ::mock_channel [open $path w]
    set code [catch {uplevel 1 $body} result options]
    close $::mock_channel
    set ::mock_channel $previous
    return -options $options $result
}
proc set_app_var {name value} {set ::$name $value}
proc shell_is_in_topographical_mode {} {return false}
proc sizeof_collection {value} {return [llength $value]}
proc get_libs {args} {
    set libs [list [dict get $::site library_name]]
    if {[lindex $args end] eq "*" && $::env(NPC_STAGE) ne "sta"} {
        lappend libs gtech standard.sldb
    }
    return $libs
}
proc get_object_name {value} {return $value}
proc foreach_in_collection {var values body} {
    foreach value $values {uplevel 1 [list set $var $value]; uplevel 1 $body}
}
proc read_db {path} {if {![file exists $path]} {error "Missing mock DB"}; set ::mock_lib_loaded 1}
proc analyze {args} {
    if {![info exists ::mock_lib_loaded]} {error "analyze before library setup"}
    foreach file [lindex $args end] {if {![file exists $file]} {error "Missing RTL $file"}}
    return 1
}
proc read_verilog {path} {if {![file exists $path]} {error "Missing netlist"}}
proc get_cells {args} {return {}}
proc all_registers {args} {
    if {[lindex $args 0] eq "-level_sensitive"} {return {}}
    return reg_pin
}
proc get_ports {args} {return [lindex $args 0]}
proc get_clocks {args} {return core_clk}
proc all_inputs {} {return {clk rst_n data}}
proc all_outputs {} {return result}
proc get_pins {args} {return {pin1 pin2 pin3}}
proc remove_from_collection {from remove} {
    set result {}; foreach item $from {if {$item ni $remove} {lappend result $item}}; return $result
}
proc get_timing_paths {args} {
    # 代表路径可以包含正 slack，但 WNS/TNS 查询必须继续严格筛选负 slack。
    set pos [lsearch -exact $args -slack_lesser_than]
    if {$pos < 0 || [lindex $args [expr {$pos+1}]] != 0.0} {error "Metrics must enumerate negative slack only"}
    return {path1 path2}
}
proc get_attribute {object name} {
    if {$name eq "slack"} {if {$object eq "path1"} {return -1.0} else {return -0.5}}
    if {$name eq "endpoint"} {return same_endpoint}
    error "Unknown mock attribute $name"
}
proc write {args} {
    set path [lindex $args end]; set f [open $path w]
    if {[lindex $args 1] eq "verilog"} {puts $f "module ysyx_core_axi4lite(); endmodule"} else {puts $f "MOCK DDC"}
    close $f
}
proc write_sdc {path} {set f [open $path w]; puts $f "MOCK EXPORTED SDC"; close $f}
# DC 2023 的实际 probe 没有 version 命令；不要用虚构的 mock 命令掩盖此错误。
proc get_app_var {name} {
    if {$name eq "sh_product_version"} {return "MOCK-VERSION-NOT-EDA"}
    if {$name eq "high_fanout_net_threshold"} {return 1000}
    error "Unknown mock application variable $name"
}
proc report_lib {name} {
    if {[file extension $name] eq ".sldb"} {
        # 模拟 UIL-29：写 Error 并返回 0，不抛 Tcl 异常，要求 driver 检查报告。
        puts "Error: The '$name' library is a synthetic library. Use report_synlib. (UIL-29)"
        return 0
    }
    puts "MOCK technology library $name"
    return 1
}
proc report_synlib {name} {
    if {$::env(NPC_STAGE) eq "sta" || $name ne "standard.sldb"} {
        error "Unexpected synthetic library report $name"
    }
    puts "MOCK synthetic library $name"
    return 1
}
proc report_area {args} {puts "Total cell area: 12.5"}
proc report_analysis_coverage {args} {puts "All Checks 10 8 (80%) 2 (20%) 0 (0%)"}
proc check_design {} {puts "MOCK check_design"; return 1}
foreach command {set_host_options define_design_lib elaborate current_design link link_design set_operating_conditions set_wire_load_mode set_wire_load_model set_fix_multiple_port_nets compile change_names update_timing create_clock set_clock_uncertainty set_clock_transition set_clock_latency set_input_delay set_input_transition set_output_delay set_load} {
    proc $command {args} {return 1}
}
foreach command {report_qor report_resources report_reference report_design check_timing report_disable_timing report_units report_wire_load} {
    proc $command {args} "puts {MOCK $command}; return 1"
}
proc all_high_fanout {args} {
    if {$args ne "-nets"} {error "Use tool threshold without overriding it"}
    if {[info exists ::env(NPC_MOCK_NO_HIGH_FANOUT)]} {return {}}
    # Deliberately not clk: catches accidental hard-coded clock-only reporting.
    return {core/reset_tree_n}
}
proc report_net {args} {
    if {$args ne "-connections -verbose core/reset_tree_n"} {error "Missing high-fanout connection detail"}
    puts "MOCK net core/reset_tree_n; driver reset_buffer/Z; loads 1379"
}
proc report_constraint {args} {
    if {[lsearch -exact $args -significant_digits] < 0} {error "Missing violation report precision"}
    puts "MOCK report_constraint"
}
proc report_timing {args} {
    if {$::env(NPC_STAGE) eq "sta"} {
        set pos [lsearch -exact $args -slack_lesser_than]
        if {$pos < 0 || [lindex $args [expr {$pos+1}]] <= 5.53} {
            error "Positive-slack representative paths would be omitted"
        }
        puts "MOCK positive path: slack (MET) 5.530000"
    } else {puts "MOCK report_timing"}
}
# Intentional unavailable optional feature. The A/timing flow must still complete.
proc set_switching_activity {args} {puts "Error: MOCK unavailable power feature"; error "MOCK unavailable power feature"}
source [lindex $argv 0]
