# 阅读测试时注意：这里以 Tcl list 模拟 EDA collection，只检查当前 top 的命名端口。
# record 记录“哪类约束作用于哪个对象”，末尾验证每个非时钟输入/输出是否有完整预算。
# 未实现的 SDC 命令会直接报错，不使用万能 unknown 空操作来假装工具支持。
# 这能发现漏约束写法，但不能验证综合网表上的端点、库单位或真实 timing coverage。
# Local SDC object/budget contract test. This is not a timing engine.
if {[catch {
    source [lindex $argv 0]
    set f [open [lindex $argv 2]]; set rtl [read $f]; close $f
    set inputs {}; set outputs {}; set all {}
    foreach {whole direction range name} [regexp -all -inline {(input|output) wire\s*(\[[0-9]+:0\])?\s*([a-zA-Z_][a-zA-Z_0-9]*)} $rtl] {
        if {$direction eq "input"} {lappend inputs $name} else {lappend outputs $name}
        lappend all $name
    }
    if {[llength $all] != 34} {error "S1 top port count changed"}
    set clock_count 0
    set assigned [dict create]
    proc get_ports {names} {
        foreach name $names {if {$name ni $::all} {error "Missing port $name"}}
        return $names
    }
    proc all_inputs {} {return $::inputs}
    proc all_outputs {} {return $::outputs}
    proc remove_from_collection {from remove} {
        set result {}; foreach name $from {if {$name ni $remove} {lappend result $name}}
        return $result
    }
    proc get_clocks {name} {
        if {$name ne "core_clk" || $::clock_count != 1} {error "Missing clock $name"}
        return $name
    }
    proc create_clock {args} {
        if {$args ne [list -name core_clk -period [dict get $::cfg period] clk]} {error "Clock contract changed"}
        incr ::clock_count
    }
    proc record {command args} {
        set mode {}
        foreach flag {-min -max -setup -hold} {if {$flag in $args} {append mode $flag}}
        foreach object [lindex $args end] {
            set key "$command:$mode:$object"
            if {[dict exists $::assigned $key]} {error "Duplicate assignment $key"}
            dict set ::assigned $key 1
        }
    }
    foreach command {set_clock_uncertainty set_clock_transition set_clock_latency set_input_delay set_input_transition set_output_delay set_load} {
        proc $command {args} "record $command {*}\$args"
    }
    source [lindex $argv 1]
    if {$clock_count != 1} {error "Expected one clock"}
    foreach p $inputs {
        if {$p eq "clk"} {continue}
        foreach command {set_input_delay:-min set_input_delay:-max set_input_transition:} {
            if {![dict exists $assigned "$command:$p"]} {error "Missing $command for $p"}
        }
    }
    foreach p $outputs {
        foreach command {set_output_delay:-min set_output_delay:-max set_load:} {
            if {![dict exists $assigned "$command:$p"]} {error "Missing $command for $p"}
        }
    }
    foreach command {set_clock_uncertainty:-setup set_clock_uncertainty:-hold set_clock_transition: set_clock_latency:-min set_clock_latency:-max} {
        if {![dict exists $assigned "$command:core_clk"]} {error "Missing $command"}
    }
    puts "SDC_CONTRACT_PASS: 1 clock, 9 non-clock inputs, 24 outputs; reset delays retained; no exceptions"
} message]} {puts stderr $message; exit 1}
