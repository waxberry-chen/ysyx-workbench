# S1 精选验证证据

2026-10-20，`make -C npc s1-test` 返回 0，S1 范围通过。设计与限制见 [实施记录](../1-axi4-interface.md)。

- [manifest.json](manifest.json)：测试输入 hash、基于的 HEAD、工具版本、逐项检查与告警分类；当前结果对应未提交工作区，不虚构新的 commit。
- [regression-summary.log](regression-summary.log)：正式 make 入口的 PASS 摘要，包含模块、译码、协议、CPU 与展开。
- [arbiter-coverage.csv](arbiter-coverage.csv)、[fabric-coverage.csv](fabric-coverage.csv)：独立 scoreboard 的74项覆盖，含顺序交叉、两种竞争胜者、各响应错误及13种复位阶段。
- [isa-results.json](isa-results.json)：97个非法编码与合法 CSR 程序，在两个延迟 seed 下的实际结果；程序自行验证 EPC/cause/GPR/CSR，runner 验证 trap 位置及访存次数。
- [memory-commit-excerpt.log](memory-commit-excerpt.log)：seed 1 的字节设备、CLINT 与不支持访问异常片段。第4/5列是本测试 trace 格式的保留零值，不是 GPR 差分证据。

完整输出在 `npc/build/m5-s1/`，ISA 生成程序/符号/trace 在 `npc/build/isa-contract-test/`。
`memory-1.fst` 是代表性波形：实际 test CPU → adapter/arbiter → router/CLINT 或独立 AXI responder。
它不表示真实 UART/APB 或 SoC MROM 已运行。重新运行上述命令即可生成，未将波形或生成 RTL 提交为手写源码。

RID/BID/RLAST 和 wrapper 的 IRQ/slave 负例共8项；PASS 表示非零退出且命中指定诊断。
10个协议 seed 每个1000笔，另有定向用例；两种 top 分别完成10132笔、复位中止11笔。
S1 不包含真实 SoC 启动、SoC DiffTest、timer IRQ、新 scope DC/PT 或完整上游 lint clean 结论。
