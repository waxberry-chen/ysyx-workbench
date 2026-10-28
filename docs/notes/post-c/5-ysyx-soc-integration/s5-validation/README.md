# M5 S5 精选验证证据

> 2026-10-28：M11–M13 定向验证通过。6 个 SoC 正向程序共 139,396 条提交、17 次 IRQ，全部分别差分；每个程序结束均比较完整 SRAM 和 PSRAM。另有 10 个随机延迟 seed 与 2 个故障检测负例。

实现及源码导读见 [S5](../5-timer-interrupt.md)。统一入口为 `make -C npc s5-test`。原始执行命令与工作区 source hash 见 `manifest.json`，结果不能只凭 base HEAD 复现。

| 程序 | 指令提交 | IRQ | CPU 周期 | 核心检查 |
| --- | ---: | ---: | ---: | --- |
| timer-registers | 6,249 | 0 | 130,713 | mtime 低位溢出、64-bit 读取、compare 重装与 MTIP |
| trap | 83 | 2 | 1,216 | masks、固定标签 EPC/cause、MRET 后立即再次 pending、非法 CSR |
| am-timer-mrom | 9,121 | 4 | 181,823 | AM event、寄存器哨兵与 ECALL 返回 |
| am-timer-flash-sram | 6,526 | 4 | 1,441,164 | Flash 真实启动后在 SRAM 运行并处理 IRQ |
| am-timer-flash-psram | 4,618 | 4 | 1,532,108 | 在 PSRAM 保存/恢复上下文 |
| rtthread-tick | 112,799 | 3 | 35,187,521 | kernel tick、嵌套临界区、IRQ nest、UART `RTT TICK PASS` |

三种 AM 布局的循环执行次数不同，因为取指/数据访问延迟不同，而 timer 按周期计数。它们不是同一个固定指令序列的性能排名。RTT 的周期包含真实 SPI 启动复制与 RAM 初始化，不是纯 IRQ 处理时间。

## 证据入口

| 文件 | 用途 |
| --- | --- |
| `manifest.json` | 主仓库、ysyxSoC、RT-Thread 版本与改动 hash；工具版本、实际命令 |
| `results.json` | S5 统一入口结果；构建条目不算工作负载 |
| `workloads.json` | 上表 6 个正向程序的原始 summary 聚合；commits/diff_steps、IRQs/diff_interrupts、timer checks、内存比较 |
| `images.json` | ELF symbol、镜像 hash、容量、栈统计；RTT 仅记录全局最低 SP，完整水位留 S6 |
| `unit-summary.txt` | EXU、CSR 两种宏配置、IDU 361,344 项独立检查、CLINT 与连续 redirect 回归 |
| `latency-summary.txt` | seed 1–10 的 CPU responder 原始结果；每次物理 store=200、data read=200，另核对提交 store 数 |
| `trap.irq.csv` | 两次入口的时间与相同 EPC；字段为 time_ps(十进制), EPC/mtime/compare(十六进制)，无表头 |
| `trap.commit.csv` | 短小的完整手写 trap 提交记录，可对照符号/反汇编确认 CSR 与 MRET |
| `irq-epc-negative.log` | mepc 取样值扰动，必须报告 `DiffTest mismatch IRQ state[19]` |
| `context-negative.log` | 恢复 t0 的 load 改 NOP，软件哨兵必须报告非零 a0 |
| `rtthread-tick.log` | 真实 RT-Thread 单线程 tick smoke 与 UART 输出 |
| `regressions.json` | S1–S4 功能回归；随后仅加强 CLINT 写事务检查并以 S5 统一入口复验，不覆盖各阶段的历史归档 |

完整 ELF/bin/map、CSV 和 FST 留在 `npc/build/m5-s5/`；`latency-1.fst` 可查看 IRQ、LSU、handler/MRET 和前端 redirect。以上源码目录中的补丁、fixture 和测试入口才是维护对象。

## 结论边界

CLINT 的计数、阈值与 MTIP 由独立逐周期模型核对；中断入口的原因、EPC 和使能还由手写程序及参考端核对。NEMU 不模拟流水线，IRQ 具体接受边沿来自 DUT 事件；优先级、漏事件与副作用还要依靠定向/随机测试和超时，不能把一次差分通过等同于形式证明。

RTT smoke 验证 tick 和单线程运行。两个线程无需主动 yield 的抢占、sleep 唤醒、线程/主栈水位和 heap 峰值继续由 S6 验收。新 CPU 范围的面积/时序仍待 S7。
