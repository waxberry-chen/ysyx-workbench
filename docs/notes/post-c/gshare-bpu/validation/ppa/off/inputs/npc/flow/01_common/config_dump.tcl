# Python 与 Tcl 的配置交接：argv[0]/argv[1] 分别是设计/site 配置路径。
# 让 Tcl 解释 Tcl 配置，而不在 Python 中用正则猜测变量展开或列表语法。
# 输出固定为“字典名 TAB 键 TAB UTF-8值的Base64”，以免路径空格、换行破坏分隔。
# Base64 只是传输编码，不是加密；配置是可信本地脚本，source 会执行其中的 Tcl。
# stdout 专供 driver 解析；错误写 stderr 并返回非零，不能混入普通调试输出。
# Run under Tcl 8.6, not an EDA shell. Configs are trusted local Tcl files.
if {[catch {
    source [lindex $argv 0]
    source [lindex $argv 1]
    foreach name {cfg site} {
        dict for {key value} [set $name] {
            puts "$name\t$key\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]"
        }
    }
} message]} {puts stderr $message; exit 1}
