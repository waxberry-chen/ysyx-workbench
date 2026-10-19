# M5 开发日志

## 2026-10-19：建立计划

- 输入：M4 已验收；本地 HEAD `d7c5b139eca8f6ffc467ecea472d4395998b1cea`。阅读 roadmap、M4 交接、原版 2607 C5/2306 B2、本地重组讲义及现有 core/AM/harness/RT-Thread 实现。
- 建立 [S0–S8 计划](plan.md)与 [M01–M18 验收矩阵](test-plan.md)，未执行 SoC 集成或修改源码。
- 关键决定：保留 B1 Lite；从 local req/rsp 边界引入保留 byte address/size 的原生 AXI4 单拍路径；CPU 内部 CLINT 与 timer interrupt 分步实现；Flash → SRAM 先证明启动，PSRAM 按真实容量纳入。
- 发现现有 RT-Thread 两线程静态栈合计 16 KiB，另有 heap > 32 KiB 断言，不适合讲义中的 8 KiB SRAM；S0 需固定容量路线，不能直接复制 B1 的 1 MiB SRAM 配置。
- 发现现有 MMIO 标记按 `0xa...` 地址判断，必须随新平台修改，否则 UART 与未来 SDRAM 的 DiffTest 分类错误。AM 中断开关当前为空实现，协作 RT-Thread 不构成中断验收证据。
- 当前无计划编写阻塞；实施前置为上游 revision/依赖生成、模型缺口审查、reset/IRQ/容量契约。在线 `ysyx6` 仅作调研线索，尚未固定或生成。
- 下一步：S0。完成后新增真实 `0-upstream-contract.md` 和验证记录；不预先创建 signoff 或填写 PASS。
