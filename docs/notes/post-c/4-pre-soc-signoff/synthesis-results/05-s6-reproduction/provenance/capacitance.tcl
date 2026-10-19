# DC/PT 共用的只读诊断：从 LSU 请求寄存器的 E pin 找实际使能网络。
# 不绑定综合产生的 U13/n3，不改变约束、CCS 设置、驱动尺寸或映射结果。
# report_net 保存工具的原始负载计算；补充属性用于解释 DC/PT 差异。
# PT L-2016.06 正文 9-7 / PDF 309：CCS receiver 可能影响报告的实际电容。

proc cap_attributes {object attributes} {
    foreach attribute $attributes {
        # 不同工具/对象支持的属性不同；不存在要写 UNAVAILABLE，不能用 0 替代。
        # -quiet 仅用于这些可选属性，核心连接查询/原始报告错误仍按 flow 失败处理。
        if {[catch {get_attribute -quiet $object $attribute} value] || $value eq ""} {
            puts "  $attribute: UNAVAILABLE"
        } else {
            puts "  $attribute: $value"
        }
    }
}

proc report_lsu_enable_capacitance {} {
    global reports stage site
    redirect -file [file join $reports checks lsu_enable_capacitance.rpt] {
        puts "NPC_LSU_ENABLE_CAPACITANCE"
        puts "stage: $stage"
        puts "tool_version: [get_app_var sh_product_version]"
        puts "library: [dict get $site library_name]"
        puts "configured_capacitance_unit: [dict get $site capacitance_unit]"
        puts "LIBRARY_FANOUT_DEFAULT: [dict get $site library_name]"
        cap_attributes [get_libs [dict get $site library_name]] {default_fanout_load}
        # 配合下方 LIB_PIN fanout_load 审查 32 的实际含义；缺失值不是零或自动为 1。
        puts "Policy: read-only; UNAVAILABLE is not zero; compare report_net and constraint_violations too."
        foreach variable {report_capacitance_use_ccs_receiver_model timing_max_capacitance_derate} {
            # 已注册的应用变量在工具 Tcl 中可见；不创建或修改未知的应用变量。
            if {[info exists ::$variable]} {
                puts "$variable: [get_app_var $variable]"
            } else {
                puts "$variable: UNAVAILABLE"
            }
        }
        # full_name 过滤跨层次匹配；get_pins 的局部名字匹配不适合带 / 的层次模式。
        # 包含 req_addr/req_wdata/req_type/req_write 各组，能找出 buffer 后的其他分支。
        set enables [get_pins -hierarchical -quiet -filter {full_name =~ core/u_lsu/req_*_q_reg*/E}]
        puts "enable_pin_count: [sizeof_collection $enables]"
        if {[sizeof_collection $enables] == 0} {
            puts "Warning: NPC_CAP_NO_ENABLE_PINS: mapping has no matching LSU E pins; review netlist; no capacitance conclusion."
        } else {
            set nets_by_name [dict create]
            foreach_in_collection pin $enables {
                set nets [get_nets -of_objects $pin]
                if {[sizeof_collection $nets] == 0} {error "LSU enable pin has no net: [get_object_name $pin]"}
                foreach_in_collection net $nets {
                    set name [get_object_name $net]
                    dict set nets_by_name $name $net
                    puts "anchor: [get_object_name $pin] -> $name"
                }
            }
            puts "enable_net_count: [dict size $nets_by_name]"
            set library_pins [dict create]
            foreach name [lsort [dict keys $nets_by_name]] {
                set net [dict get $nets_by_name $name]
                puts "NET: $name"
                report_net -connections -verbose $net
                # 补充 DC 的电容视图（手册 8-9）。2023 版实测输出 Load/LoadUR/
                # LoadUF 等列，不能假定与旧手册一样含 Required/Actual/Slack。
                if {$stage eq "syn"} {report_net -max_capacitance $net}
                cap_attributes $net {wire_capacitance_min wire_capacitance_max total_capacitance_min total_capacitance_max}
                set drivers 0
                set loads 0
                foreach_in_collection pin [get_pins -of_objects $net] {
                    set pin_name [get_object_name $pin]
                    set direction [get_attribute $pin direction]
                    if {$direction eq "out"} {incr drivers}
                    if {$direction eq "in"} {incr loads}
                    set cell [get_cells -of_objects $pin]
                    set reference [get_attribute $cell ref_name]
                    puts "PIN: $pin_name direction=$direction reference=$reference"
                    # 工具的设计 pin 属性与库 pin 属性分开，不能把库输入电容当作 CCS 实际值。
                    cap_attributes $pin {max_capacitance min_capacitance total_ccs_capacitance_max_rise total_ccs_capacitance_max_fall total_ccs_capacitance_min_rise total_ccs_capacitance_min_fall}
                    set lib_name "[dict get $site library_name]/$reference/[file tail $pin_name]"
                    dict set library_pins $lib_name 1
                }
                puts "direct_output_pin_count: $drivers"
                puts "direct_input_pin_count: $loads"
            }
            # 同型号的 E pin 只报告一次库值；上面的 PIN 记录仍列出每个实际负载。
            foreach name [lsort [dict keys $library_pins]] {
                puts "LIB_PIN: $name"
                set lib_pin [get_lib_pins -quiet $name]
                if {[sizeof_collection $lib_pin] != 1} {
                    puts "Warning: NPC_CAP_LIB_PIN_UNAVAILABLE: $name"
                } else {
                    cap_attributes $lib_pin {direction fanout_load capacitance rise_capacitance fall_capacitance max_capacitance min_capacitance}
                }
            }
        }
        puts "NPC_LSU_ENABLE_CAPACITANCE_END"
    }
}
