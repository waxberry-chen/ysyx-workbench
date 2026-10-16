# 共享 EDA 初始化：由 probe/synthesis/STA 入口 source，不直接用普通 tclsh 运行。
# set_app_var/get_libs 等是 Synopsys 命令；dict/file/proc 则属于 Tcl 本身。
# $name 取变量值，[command ...] 取命令结果；花括号包住过程体，使其稍后执行。
# Entrypoints only use the launcher's snapshot, never source ambient config files.
# 1. driver 通过环境变量传入快照路径；run.tcl 定义 run、cfg、site、rtl_sources。
# source 会在当前 Tcl 解释器执行文件，不会另起进程。
source $::env(NPC_RUN_CONFIG)
set npc_root [file join $run inputs npc]
set flow [file join $npc_root flow]
set top [dict get $cfg top]
set stage $::env(NPC_STAGE)
set reports [file join $run reports $stage]
set outputs [file join $run outputs]
file mkdir $reports $outputs
# 所有 RTL/include 路径从快照中的 npc/ 解析，而不是从服务器原工作区解析。
cd $npc_root
set_host_options -max_cores [dict get $cfg max_cores]
# DC V-2023.12-SP5 实测没有 version 命令；读取 shell 的产品版本变量。
# get_app_var 返回字符串，必须显式 puts 才能写进 redirect 的报告。
redirect -file [file join $reports version.rpt] {puts [get_app_var sh_product_version]}
# 部分 EDA 命令失败时返回 0，不一定抛出 Tcl 异常；把布尔失败转换为 error。
# 此函数只用于已约定返回布尔值的命令；driver 还会检查日志中的 Error。
proc require_true {value message} {
    if {$value ne "1" && $value ne "true"} {error $message}
}
# 2. 库必须先于 design 的展开/link 配置，确保实例能找到正确定义。
# DC P-2019.03 正文 4-10 / PDF 120：target 与 link/synthetic 库角色不同。
proc libraries {} {
    global site stage
    set db [dict get $site target_db]
    # search_path 是缺省查找目录；显式 DB 路径仍优先避免同名库被误选。
    set_app_var search_path [concat [list [file dirname $db]] $::search_path]
    if {$stage eq "syn" || $stage eq "probe"} {
        # target_library：允许 DC 将逻辑映射到哪些工艺单元。
        # synthetic_library：HDL 算术等运算的综合实现；standard.sldb 是工具内置库，
        # 并不表示用它替代真实工艺单元库，也不等同于额外的 dw_foundation.sldb。
        # link_library：解析模块/单元引用；星号表示搜索内存中的设计，不是磁盘文件 glob。
        set_app_var target_library [list $db]
        set_app_var synthetic_library [list standard.sldb]
        set_app_var link_library [list * $db standard.sldb]
    } else {
        # PT 不做逻辑映射，只解析已映射网表中的引用，故使用 link_path。
        set_app_var link_path [list * $db]
    }
    read_db $db
}
# 将实际加载的库内容留下，而非只保存一个未经核对的文件名。
# get_libs 返回 EDA collection；foreach_in_collection 用于遍历这类工具对象。
proc library_reports {} {
    global reports
    foreach_in_collection lib [get_libs *] {
        set name [get_object_name $lib]
        # 当前 DC 的 synthetic_library 只配置 standard.sldb，get_libs * 也会列出它。
        # .sldb 描述算术等综合运算；工艺 .db/gtech 则使用 report_lib。
        # DC P-2019.03 PDF 429 示例：report_synlib standard.sldb。
        # 不能把所有库都改成 report_synlib；PT 不配置 synthetic_library。
        if {$::stage ne "sta" && [file extension $name] eq ".sldb"} {
            redirect -file [file join $reports "library_${name}.rpt"] {report_synlib $name}
        } else {
            redirect -file [file join $reports "library_${name}.rpt"] {report_lib $name}
        }
    }
}
# 3. link 后设置工作条件和互连估算；DC 与 PT 共用此过程，减少假设漂移。
# operating condition 包含库中的 PVT 条件；单角基线不能推广为所有角均通过。
proc environment {} {
    global site
    set lib [dict get $site library_name]
    if {[sizeof_collection [get_libs $lib]] != 1} {error "Configured library name not loaded: $lib"}
    set_operating_conditions [dict get $site operating_condition] -library $lib
    # WLM（wire load model）按 fanout 等统计量估计互连，不是真实布线提取。
    # 禁止按面积自动换模型；top mode 表示跨层次互连使用顶层的模型策略，
    # 不表示 topographical 模式。后者需要物理实现信息，本轮未启用。
    # 依据：DC 正文 7-15 / PDF 207；PT L-2016.06 正文 5-10 / PDF 154。
    set_app_var auto_wire_load_selection false
    set_wire_load_mode top
    if {[dict get $site wire_load_model] ne "library_default"} {
        set_wire_load_model -name [dict get $site wire_load_model] -library $lib
    }
    # library_default is intentional: actual default or absent-model behavior
    # must be recorded from report_design/report_wire_load, not called zero RC.
}
# 4. 只有主步骤执行到末尾才写完成标记。标记不是 timing PASS；
# Python 还要检查退出码、日志、产物和 coverage，避免“文件存在就算成功”。
proc complete {} {
    global reports stage
    set f [open [file join $reports complete.txt] w]
    puts $f "NPC_FLOW_COMPLETE $stage"
    close $f
}
