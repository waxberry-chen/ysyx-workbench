# 库探测入口：只检查工具能否启动/读库，并输出 version.rpt 与 library_*.rpt。
# 不读取 RTL、不 compile，所以此步骤没有 NPC 面积或时序结论。
# 先用报告确认库内部名、operating condition、单位和默认 WLM，再填写 site。
# 最外层 catch 将 Tcl 异常转换成非零进程退出码，供 Python driver 识别。
if {[catch {
    source [file join $::env(NPC_FLOW_SNAPSHOT) common setup.tcl]
    libraries
    library_reports
    complete
} message]} {puts stderr "NPC_FLOW_ERROR: $message"; exit 1}
exit 0
