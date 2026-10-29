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
proc read_db {path} {
    if {![file exists $path]} {error "Missing mock DB"}
    set ::mock_lib_loaded 1
    set lib [dict get $::site library_name]
    # 两个不同的输出上限，以及一个没有上限的特殊输出，防止统一绝对值/重复缩放。
    set ::mock_lib_caps [dict create $lib/INVD1/ZN 0.084770 $lib/BUFFD1/Z 0.200000 $lib/TIE/Z ""]
    if {[info exists ::env(NPC_MOCK_CAP_SIX_DECIMALS)]} {
        # 服务器实际误报：0.021655 * 0.90 = 0.0194895，回读为 0.019490。
        dict set ::mock_lib_caps $lib/OAI32D0/ZN 0.021655
    }
    set ::mock_original_caps $::mock_lib_caps
    set ::mock_compile_count 0
}
proc analyze {args} {
    if {![info exists ::mock_lib_loaded]} {error "analyze before library setup"}
    foreach file [lindex $args end] {if {![file exists $file]} {error "Missing RTL $file"}}
    return 1
}
proc read_verilog {path} {if {![file exists $path]} {error "Missing netlist"}}
# Deliberately different names and two enable branches: discovery must not depend on U13/n3.
set cap_a subsystem/cpu/core/u_lsu/enable_renamed_a
set cap_b subsystem/cpu/core/u_lsu/enable_renamed_b
set cap_driver subsystem/cpu/core/u_lsu/renamed_driver
set cap_buffer subsystem/cpu/core/u_lsu/renamed_buffer
set cap_enables {subsystem/cpu/core/u_lsu/req_addr_q_reg_0_/E subsystem/cpu/core/u_lsu/req_wdata_q_reg_1_/E subsystem/cpu/core/u_lsu/req_type_q_reg_0_/E}
set cap_connections [dict create $cap_a [concat [list $cap_driver/ZN] [lrange $cap_enables 0 1] [list $cap_buffer/I]] \
    $cap_b [list $cap_buffer/Z [lindex $cap_enables 2]]]
if {$::env(NPC_STAGE) eq "sta"} {
    set report_capacitance_use_ccs_receiver_model true
    set timing_max_capacitance_derate 1.0
}
proc get_cells {args} {
    if {[lindex $args 0] eq "-of_objects"} {return [file dirname [lindex $args 1]]}
    return {}
}
proc current_design {args} {
    if {[llength $args]} {set ::mock_current_design [lindex $args 0]}
    return $::mock_current_design
}
proc set_max_fanout {value objects} {
    if {$::env(NPC_STAGE) ne "syn" || $objects ne $::top || $value != 32} {
        error "Max fanout must be 32 on synthesis top"
    }
    set ::mock_syn_max_fanout $value
}
proc set_auto_disable_drc_nets {args} {
    if {$::env(NPC_STAGE) ne "syn" || $args ne {-on_clock_network true}} {
        error "Only clock network DRC fixing may be disabled"
    }
    if {[info exists ::env(NPC_MOCK_CLOCK_DRC_COMMAND_ERROR)]} {error "Injected clock DRC command failure"}
    set ::mock_clock_drc_disabled true
}
proc mock_power_optimization {kind value} {
    if {$::env(NPC_STAGE) ne "syn" || $value ne "false"} {error "Power optimization must be disabled in synthesis"}
    if {[info exists ::env(NPC_MOCK_POWER_POLICY_ERROR)] && $::env(NPC_MOCK_POWER_POLICY_ERROR) eq $kind} {
        error "Injected $kind policy failure"
    }
    dict set ::mock_power_policy $kind $value
}
proc set_leakage_optimization {value} {mock_power_optimization leakage $value}
proc set_dynamic_optimization {value} {mock_power_optimization dynamic $value}
proc compile_ultra {args} {
    if {$::mock_compile_count == 0} {
        if {$args ne {-no_autoungroup}} {error "Unexpected initial Ultra options"}
    } elseif {$::mock_compile_count == 1} {
        if {$args ne {-incremental -only_design_rule}} {error "Unexpected incremental DRC options"}
    } else {error "Unexpected extra compile"}
    incr ::mock_compile_count
    dict for {pin original} $::mock_original_caps {
        if {$original ne "" && abs([dict get $::mock_lib_caps $pin] - 0.9*$original) > 1e-9} {
            error "Missing per-library-pin margin before compile"
        }
    }
    foreach kind {leakage dynamic} {
        if {![info exists ::mock_power_policy] || ![dict exists $::mock_power_policy $kind] ||
            [dict get $::mock_power_policy $kind] ne "false"} {
            error "Missing explicit $kind policy before compile_ultra"
        }
    }
    if {![info exists ::mock_syn_max_fanout]} {error "Missing top fanout before compile"}
    if {![info exists ::mock_clock_drc_disabled]} {error "Clock DRC protection missing before compile"}
    if {[info exists ::env(NPC_MOCK_DROP_SYN_FANOUT)]} {unset ::mock_syn_max_fanout}
    if {[info exists ::env(NPC_MOCK_DROP_CLOCK_DRC)]} {set ::mock_clock_drc_disabled false}
    if {[info exists ::env(NPC_MOCK_ULTRA_FAILURE)]} {return 0}
    if {[info exists ::env(NPC_MOCK_INCREMENTAL_FAILURE)] && $::mock_compile_count == 2} {return 0}
    if {[info exists ::env(NPC_MOCK_DROP_CAP_MARGIN)]} {set ::mock_lib_caps $::mock_original_caps}
    return 1
}
proc all_registers {args} {
    if {[lindex $args 0] eq "-level_sensitive"} {return {}}
    return reg_pin
}
proc get_ports {args} {return [lindex $args 0]}
proc get_clocks {args} {return core_clk}
proc all_inputs {} {return {clock reset io_interrupt io_master_rdata}}
proc all_outputs {} {return result}
proc get_pins {args} {
    if {[lindex $args 0] eq "-of_objects"} {return [dict get $::cap_connections [lindex $args 1]]}
    if {[lsearch -exact $args -filter] >= 0} {
        if {[lindex $args end] ne {full_name =~ subsystem/cpu/core/u_lsu/req_*_q_reg*/E}} {error "Unexpected enable selection"}
        if {[info exists ::env(NPC_MOCK_NO_ENABLE_PINS)]} {return {}}
        return $::cap_enables
    }
    return {pin1 pin2 pin3}
}
proc get_nets {args} {
    if {[lindex $args 0] ne "-of_objects"} {error "Enable nets must be discovered from pins"}
    set pin [lindex $args 1]
    if {$pin eq $::clock_port} {return clk_net}
    dict for {net pins} $::cap_connections {if {$pin in $pins} {return $net}}
    error "Unknown mock net for $pin"
}
proc get_lib_pins {args} {
    if {[lsearch -exact $args -filter] >= 0} {
        set expected [list -quiet [dict get $::site library_name]/*/* -filter {direction == out || direction == inout}]
        if {$::env(NPC_STAGE) ne "syn" || $args ne $expected} {error "Margin must select only target-library output pins"}
        if {[info exists ::env(NPC_MOCK_NO_CAP_OUTPUTS)]} {return {}}
        return [dict keys $::mock_lib_caps]
    }
    return [lindex $args end]
}
proc set_attribute {pin name value} {
    if {$::env(NPC_STAGE) ne "syn" || $name ne "max_capacitance" ||
            ![dict exists $::mock_lib_caps $pin] || [dict get $::mock_original_caps $pin] eq ""} {
        error "Only existing target-library output max_capacitance may be changed in DC"
    }
    if {[info exists ::env(NPC_MOCK_CAP_SET_ERROR)]} {error "Injected library attribute write failure"}
    if {![info exists ::env(NPC_MOCK_CAP_SET_IGNORED)]} {dict set ::mock_lib_caps $pin $value}
    return $pin
}
proc remove_from_collection {from remove} {
    set result {}; foreach item $from {if {$item ni $remove} {lappend result $item}}; return $result
}
proc get_timing_paths {args} {
    # 代表路径可以包含正 slack，但 WNS/TNS 查询必须继续严格筛选负 slack。
    set pos [lsearch -exact $args -slack_lesser_than]
    if {$pos < 0 || [lindex $args [expr {$pos+1}]] != 0.0} {error "Metrics must enumerate negative slack only"}
    return {path1 path2}
}
proc get_attribute {args} {
    set object [lindex $args end-1]
    set name [lindex $args end]
    if {$name eq "max_capacitance" && [dict exists $::mock_lib_caps $object]} {
        if {[info exists ::env(NPC_MOCK_NO_CAP_LIMITS)]} {return ""}
        set value [dict get $::mock_lib_caps $object]
        if {$value eq ""} {return ""}
        if {[info exists ::env(NPC_MOCK_CAP_SIX_DECIMALS)]} {
            # 半末位处给极小浮点余量，稳定复现服务器向上舍入的回读文本。
            return [format %.6f [expr {$value + 1e-15}]]
        }
        return [format %.9f $value]
    }
    if {$name eq "max_fanout" && $object eq $::top} {
        if {[info exists ::mock_syn_max_fanout]} {return $::mock_syn_max_fanout}
        error "Mock design fanout missing"
    }
    if {$name eq "auto_disable_drc_nets" && $object eq "clk_net"} {
        # 默认重现服务器：命令可用，但该 net 属性不可查询；不伪造为 true。
        if {[info exists ::env(NPC_MOCK_DROP_CLOCK_DRC)]} {return $::mock_clock_drc_disabled}
        if {[lsearch -exact $args -quiet] < 0} {
            puts "Warning: Attribute 'auto_disable_drc_nets' does not exist on net 'clk_net'. (UID-101)"
        }
        return ""
    }
    if {$name eq "default_fanout_load"} {return 1.0}
    # A non-unit explicit weight catches accidental interpretation as pin count.
    if {$name eq "fanout_load" && [string match */EDFCNQD1/E $object]} {return 2.0}
    if {$name eq "slack"} {if {$object eq "path1"} {return -1.0} else {return -0.5}}
    if {$name eq "endpoint"} {return same_endpoint}
    if {$name eq "direction"} {if {[file tail $object] in {E I}} {return in} else {return out}}
    if {$name eq "ref_name"} {
        if {$object eq $::cap_driver} {return INVD1}
        if {$object eq $::cap_buffer} {return BUFFD1}
        return EDFCNQD1
    }
    if {$name eq "max_capacitance" && [file tail $object] eq "ZN"} {
        return [format %.9f [dict get $::mock_lib_caps [dict get $::site library_name]/INVD1/ZN]]
    }
    if {$name eq "capacitance" && [string match */EDFCNQD1/E $object]} {return 0.001}
    if {$name eq "total_ccs_capacitance_max_rise" && $::env(NPC_STAGE) eq "sta" && $object eq "$::cap_driver/ZN"} {return 0.088724}
    # Most optional attributes are intentionally unavailable in this fixture.
    error "Unknown mock attribute $name"
}
proc write {args} {
    if {$::env(NPC_STAGE) eq "syn" && $::mock_compile_count != 2} {error "Export before incremental DRC fixing"}
    set path [lindex $args end]; set f [open $path w]
    if {[lindex $args 1] eq "verilog"} {puts $f "module ${::top}(); endmodule"} else {puts $f "MOCK DDC"}
    close $f
}
proc write_sdc {path} {set f [open $path w]; puts $f "MOCK EXPORTED SDC"; close $f}
# DC 2023 的实际 probe 没有 version 命令；不要用虚构的 mock 命令掩盖此错误。
proc get_app_var {name} {
    if {$name eq "sh_product_version"} {return "MOCK-VERSION-NOT-EDA"}
    if {$name eq "high_fanout_net_threshold"} {return 1000}
    if {$name in {report_capacitance_use_ccs_receiver_model timing_max_capacitance_derate} && [info exists ::$name]} {return [set ::$name]}
    error "Unknown mock application variable $name"
}
proc report_lib {name} {
    if {$::mock_lib_caps ne $::mock_original_caps} {error "Original library report must precede margin"}
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
proc set_false_path {args} {
    if {$args ne [list -from $::reset_port]} {error "Only the scope reset may be excluded"}
    return 1
}
# 本次诊断不执行 set_fix_multiple_port_nets；不提供该命令的无操作替身，
# 防止真实 Tcl 在测试中悄悄恢复强制 buffer 策略。是否消除电气违例需真实 EDA 验证。
foreach command {set_host_options define_design_lib elaborate link link_design set_operating_conditions set_wire_load_mode set_wire_load_model change_names update_timing create_clock set_clock_uncertainty set_clock_transition set_clock_latency set_input_delay set_input_transition set_output_delay set_load set_case_analysis} {
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
    if {[dict exists $::cap_connections [lindex $args end]]} {
        if {[lrange $args 0 end-1] eq {-max_capacitance} && $::env(NPC_STAGE) eq "syn"} {
            puts "MOCK DC capacitance view Load LoadUR LoadUF"
            return
        }
        if {[lrange $args 0 end-1] ne {-connections -verbose}} {error "Missing capacitance connection details"}
        if {[info exists ::env(NPC_MOCK_CAP_REPORT_ERROR)]} {error "Injected capacitance report failure"}
        puts "MOCK capacitance net [lindex $args end]; stage $::env(NPC_STAGE)"
        return
    }
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
