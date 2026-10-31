# GShare 本地验收证据入口

这里保存小型、值得随代码维护的结果。完整日志、生成镜像、仿真器与 trace 留在 `npc/build/gshare-bpu/`，EDA 产物在 `npc/flow/build/`。没有归档或伪造服务器 DC/PT 结果。

建议阅读顺序：

1. [S1 说明](../1-predictor.md)与 [unit-results.json](unit-results.json)：单元命令／预期失败项。`unit-*.log` 保存关键实际输出，特别是两个检查器负例的精确诊断。
2. [targeted.json](targeted.json)、[targeted.log](targeted.log) 与 [S3 说明](../3-functional-validation.md)：新增错误路径与复用 M5 suites 的用途；[system-summary.json](system-summary.json) 按实际 summary 汇总146次正向 SoC 运行，[system-manifest.json](system-manifest.json) 保存 S6 命令／输入追溯，[system.log](system.log) 保存全套执行输出。完整逐程序产物在 `npc/build/gshare-bpu/system/`。
3. [trace 分支计数校验](trace-branch-counts.json)与 [S4 结果](../4-performance-ppa.md)与 [performance.json](performance.json)：18 份 summary、命令、二进制／参考端／镜像／trace hash 和测量源文件 hash。
4. [scope.json](scope.json)、[flow-tests.log](flow-tests.log)：三模式 × 四宏 profile 的源闭包／告警审查，以及 57 个 mock 流程检查。mock 中故意失败的日志不是实际 EDA 报告。
5. [阶段状态](../signoff.md)：当前通过范围和服务器待办。

测量基于起点 commit `a7f4000` 加工作区实现，不能只用起点 SHA 代表最终代码。性能原始 hash 没有改写；测量后曾移除 `ysyx_core.sv` 一行注释的尾空格，已在 [post-measurement-formatting.json](post-measurement-formatting.json) 精确记录前后 hash，RTL token 未变化。

重新运行入口：

```bash
make -C npc bpu-test
make -C npc bpu-performance
make -C npc bpu-system
make -C npc/flow check test scope-check
```

`bpu-test` 不依赖 SoC 生成或软件镜像。`bpu-performance` 需要 M5 冻结的六个 `artifacts/m5-s8-20261030/comparison/` 镜像，按原清单检查 SHA-256；缺文件时会停止，不能静默改用重新编译的输入。`bpu-system` 使用当前源码构建软件和 DUT，软件编译出的 `.elf/.bin` 保存在独立输出目录，不覆盖冻结的六程序输入。

实施问题与修正见 [development-failures.md](development-failures.md)。[handoff-source.json](handoff-source.json) 是当前实现的源码交接 hash；它与各测量 manifest 的实际运行输入分开保存，不能用交接 hash 覆盖原测量记录。
