# M5 面试 Q&A

> 2026-10-19：以下是规划阶段的设计依据，尚非实现结果。随有价值的设计/验证进展补充，不要求每次修改都记录。实现与证据入口见 [计划](../plan.md)。

## Q1：已有 AXI4-Lite，为什么不能只加 LEN、SIZE 等端口接入 SoC？

当前 LSU Lite adapter 已将地址按 word 对齐，Lite 读接口也没有携带访问 size。下游 wrapper 无法恢复原来的 byte address 和读宽度。UART 等 byte 寄存器可能有读取副作用，整字读后截取数据不一定等价于一次 byte 读。

因此计划从现有 IFU/LSU local req/rsp 处保留原始信息，新增 AXI4 单拍 transport，固定 `LEN=0` 也能正确表达窄访问。B1 的 Lite 配置继续保留；暂不实现 burst 或多 outstanding，并不意味着可以丢弃 size、ID/响应匹配和独立通道握手语义。

## Q2：Flash 启动和可写内存容量有什么关系？为什么不能直接搬用 B1 的 RT-Thread？

Flash 提供程序初始内容，但 `.data/.bss`、栈和 heap 仍需要可写存储。Flash 的映射窗口也不等于 SRAM 容量。讲义中 SRAM 只有 8 KiB，而本项目 B1 fixture 两个静态线程栈已占 16 KiB，还要求 heap 超过 32 KiB。

计划先用小程序完成 Flash → SRAM 的复制/清零/跳转，再按 ELF/map 与运行余量选择 RT-Thread 的存储方案，预期需要 PSRAM。验证启动时只加载 Flash/MROM，目标 RAM 预填图案，让 CPU 执行真实搬运，避免 harness 预加载 RAM 掩盖 bootloader 错误。

## Q3：能读 mtime、能运行 RT-Thread，是否代表支持中断？

都不代表。当前 CLINT 只有计时器，B1 RT-Thread 通过主动 yield 协作切换。timer interrupt 还需要 mtimecmp/pending、CSR mask、精确接受边界、trap/MRET，以及 AM 与 RT-Thread 的 tick/中断开关和调度。

验收要让没有主动 yield 的线程也因 tick 得到运行机会，并检查 cause、EPC、上下文与访存副作用。上游 `io_interrupt` 是外部中断输入，与 CPU 内部 timer pending 分开；不能仅把 DUT 的 cause 注入 NEMU 后状态一致当成中断检测正确的证明。
