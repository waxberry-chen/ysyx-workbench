# 实施中定位并解决的问题

以下是执行记录整理的失败摘录与原因，不冒充完整原始日志。检查器预期失败的完整短日志另见 `unit-metadata-negative.log` 和 `unit-recovery-negative.log`。

| 现象／实际诊断 | 定位与修正 |
| --- | --- |
| Verilator 5.008：`Unsupported: Delayed assignment to array inside for loops` (`BLKLOOPINIT`) | 初稿在 reset 的 procedural for 中重置 128 项 PHT；改为 generate 展开每项时序块，保留 nonblocking／共同 reset 语义。N=7/N=3 独立模型均通过。 |
| `BPU_RECOVERY: predicted JAL/link` | 新测试把 EXU writeback mux 选成 2（load data），应为 1（PC+4）；修正测试刺激，RTL writeback 没有修改。 |
| 错误取指版本的 predicted-T/actual-NT 数量少一条 | 反汇编发现 GNU assembler 把绝对地址 branch 改写为反向 branch + JAL，破坏了预定 victim PC/编码；使用显式 BNE 编码，补查真实总线请求／错误响应，五种错误目标均通过。 |
| `Implementation defines must match the frozen scope profile` | flow 原来严格限定两个宏，尚未允许 BPU 模式。现只允许基础宏加明确的 mode=0/1/2，且实际模式进入 snapshot/manifest；未知／重复／缺失模式继续拒绝。57 项 mock 检查通过。 |
| ccache 无法在 `/run/user/1000/ccache-tmp` 创建临时文件 | 沙箱环境问题；失败命令按权限流程重试，后续新 runner 改用自身 build 下的缓存目录。不是 RTL／协议失败。 |

这些问题已解决。未关闭项是新的服务器面积／时序对照，见 [S4](../4-performance-ppa.md)。
