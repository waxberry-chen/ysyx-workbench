# 工艺库输入

将服务器使用的 DB 放在本目录，例如
`STD_NEW/tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs.db`。
DB 内容被 Git 忽略，flow 只记录其绝对路径和 hash，不复制到每次 run。

在 `../configs/site.local.tcl` 设置 `target_db` 的实际绝对路径。
示例默认指向此位置；外部服务器绝对路径也支持。
`make clean RUN_ID=...` 不删除本目录。
