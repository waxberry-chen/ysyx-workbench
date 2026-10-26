# M5 S4 精选验证证据

> 2026-10-26：统一 `make -C npc s4-test` 通过；965,839 次提交全部差分，41 次 SRAM 与 41 次 PSRAM 全内存比较通过。M09/M10 PASS。

实现与源码导读见 [S4](../4-boot-memory.md)。实际命令、源文件 hash、子模块状态及工具版本见 [manifest.json](manifest.json)；它记录未提交的工作区源码，不能只用 base HEAD 复现。

本轮包含 **41 个正向 workload**：SPI/Flash 对照、PSRAM 存储、Flash reset XIP、8 项存储异常组成的程序、两种 RAM 启动、34 个 CPU tests、1 个 RT-Thread 协作式容量 workload。另有 4 个缺失 data-copy/bss-clear 负例、2 个 Flash 镜像容量负例、3 个 linker 容量负例。构建/objcopy 也在 results 中，不能把 results 条目数当作 workload 数。

| 文件 | 用途 |
| --- | --- |
| [manifest.json](manifest.json) | 实际源码/生成产物 hash、版本、命令、通过范围 |
| [results.json](results.json)、[run-summary.txt](run-summary.txt) | 统一 S4 入口的结果；正向测试与预期失败区分 |
| [workloads.json](workloads.json) | 每个正向 workload 的提交、总线、器件访问、逐条差分与最终 RAM 检查计数 |
| [images.json](images.json)、[memory-layout.txt](memory-layout.txt) | 镜像 hash、symbol、VMA/LMA、静态占用、heap/stack 预算 |
| [cpu-tests.json](cpu-tests.json) | 35 项分类：34 PASS；unalign 因当前 ISA 对齐策略排除 |
| [boot-flash-sram-startup.json](boot-flash-sram-startup.json)、[boot-flash-psram-startup.json](boot-flash-psram-startup.json) | 按提交 PC 分类并逐地址核对 poison、text/data copy、bss clear 的 store |
| [boot-commit-excerpt.txt](boot-commit-excerpt.txt) | 首条 Flash 指令、复制/清零指令和首次 RAM 入口的精选提交 |
| `spi/psram/xip/storage-faults/boot-flash-*/rtthread-capacity.log` | 代表性原始运行日志；负例日志的名称带 missing/overflow/oversized/empty |
| [s1-regression.json](s1-regression.json)、[s2-regression.json](s2-regression.json)、[s3-regression.json](s3-regression.json) | 当前范围变更后的 S1/S2/S3 回归；不改写历史归档 |
| [am-run.log](am-run.log) | 真实 `ARCH=riscv32e-ysyxsoc SOC_BOOT=flash-psram run` 入口 |

所有正向 workload 的每条提交均比较，结束时各核对一次完整 8 KiB SRAM 和 4 MiB PSRAM；没有全状态 skip。Flash/PSRAM 是普通存储，SPI 寄存器的设备读值同步不能代替已知 Flash pattern 的独立自检。

## RT-Thread 容量结果

| 项目 | 实测/预算 |
| --- | --- |
| Flash 镜像 | 21,832 B |
| RAM 静态区间（含对齐） | 42,992 B：`0x80000000..0x8000a7ef` |
| 两个测试线程的静态栈 | 每个 8,192 B，已含在静态区间内，不能重复加到总占用 |
| 主栈预留 | 65,536 B：`0x803f0000..0x803fffff` |
| linker 提供的 heap | 4,085,776 B：`0x8000a7f0..0x803effff`；不是 kernel 元数据初始化后的净可分配量 |
| 最低观测 SP | `0x800073a8`，位于第一个静态线程栈内；距该栈下界 7,960 B |
| 运行检查 | 双线程 `AB` 交替 100 轮；分配缓冲区内容正确；释放后 heap used 恢复；kernel 记录的 peak 大于恢复值、低于 total |

最低 SP 是全部提交的全局最小值，不能据此算主栈用量或第二个线程的峰值；kernel 的栈溢出检查已启用。本步没有单独归档各线程/主栈的完整水位和数值化 heap 峰值，S6 系统验收继续补充。S4 的结论是本 workload 能真实装载并运行，有明确存储预算和运行中的容量检查。

203 次异常来自 ECALL 协作式调度，不是 timer interrupt。本次复用历史 workload 的 C 测试与 RT-Thread kernel/BSP，通过新的 SoC/Flash/PSRAM 路径运行，不恢复 B1 硬件或旧 harness。

## 可复现范围

```bash
make -C npc s4-test
make -C npc s1-test
make -C npc s2-test
make -C npc s3-test
```

编译产物、完整 ELF/map/反汇编、commit/bus CSV 在 `npc/build/m5-s4/`。额外捕获的 `xip.fst`（真实串行首取指）和 `boot-flash-sram.fst`（完整 Flash→SRAM 启动）也留在该目录；manifest 记录捕获命令与 hash，不提交 FST/二进制/生成 RTL。

等待覆盖来自真实 SPI/PSRAM 串行延迟与 guard 的独立随机 backpressure 测试；不宣称全系统随机延迟注入、中途 reset 恢复、完整颗粒 AC 时序或抢占 RTOS 验收。S5/S6 继续 timer IRQ/系统功能，S7 再建立新的综合边界。
