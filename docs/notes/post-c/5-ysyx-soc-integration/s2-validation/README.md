# S2 验收证据

2026-10-20，CPU 顶层改为 `ysyx_25030087` 后重新生成，`make -C npc s2-test`、完整 `make -C npc s1-test` 及61-port接口检查均通过。四个程序的统计与改名前一致，精选 CSV 逐字节一致，见 [rename-check.json](rename-check.json)。设计和重建命令见 [S2 实施记录](../2-bringup.md)。

## 版本与结果

- [manifest.json](manifest.json)：主仓库/ysyxSoC/Rocket Chip 基础 HEAD、108 个源文件 hash、生成 SoC hash、镜像大小/hash、FST 路径/hash。记录的是未提交工作区，不能仅 checkout 基础 HEAD 宣称复现本次结果。
- [generation.log](generation.log)：修改 Scala 后实际生成的日志；不是只检查旧 Verilog 存在。
- [results.json](results.json)、[guard.log](guard.log)：S2 构建、真实运行、独立 guard 检查及预期失败项；每项有独立退出码检查，harness 单项上限30000周期，进程上限240秒。
- [s1-regression-results.json](s1-regression-results.json)：改名后的 S1 完整回归，与 S2 对应同一版功能源码。
- [build-diagnostics.txt](build-diagnostics.txt)：最终 SoC 编译共165条非致命告警；`WIDTH/PINMISSING/PINNOTFOUND/LATCH/UNOPTFLAT/UNDRIVEN` 均设为致命且为0。未宣称整个上游 lint clean。

非致命告警主要为上游未用信号/参数、空命名连接、多模块文件名及旧式 defparam/时钟过程赋值。SYNCASYNCNET 被显式抑制：含 reset 同步观察/异步复位以及上游延时数据采样，物理 reset 验证仍按 S7 计划处理。原 S0 GPIO/PS2/VGA 的24项 UNDRIVEN 已消除；设备功能仍禁用。

| 程序 | 完整周期 | commit | exception | AR/R | AW/W/B | 结果 |
| --- | ---: | ---: | ---: | --- | --- | --- |
| [ebreak](ebreak.json) | 44 | 1 | 0 | 1/1 | 0/0/0 | 首 PC/指令正确 |
| [uart](uart.json) | 695 | 36 | 0 | 45/45 | 7/7/7 | 实际 TX 精确一个 A |
| [memory](memory.json) | 745 | 46 | 0 | 54/54 | 4/4/4 | 首尾与窄访存/合并写自检通过 |
| [faults](faults.json) | 7576 | 464 | 32 | 576/576 | 17/17/17 | cause/EPC、bus error、副作用检查通过 |

cycles 计完整下降沿数，最后一条 commit 可能在下一上升沿退出；不能据44 cycles把445ns的提交误判为时间统计错误。各程序 Flash DPI 调用均为0，S2 不提供 Flash/XIP功能结论。

## 取指与 UART 原始观察

完整 FST 留在 `npc/build/m5-s2/{ebreak,uart,memory,faults}.fst`，运行脚本可重建，hash见manifest。此处保留小型原始CSV，便于不用波形工具也能复核。

| 文件 | CSV 列（无表头，保持原始输出） |
| --- | --- |
| [ebreak.bus.csv](ebreak.bus.csv)、[uart.bus.csv](uart.bus.csv) | time_ps十进制、握手flags十进制、ARADDR/AWADDR/WDATA/RDATA/ARSIZE/AWSIZE/WSTRB/RRESP/BRESP均十六进制；flags位为AR=1/AW=2/W=4/R=8/B=16，仅置位通道payload有意义 |
| [ebreak.commit.csv](ebreak.commit.csv)、[uart.commit.csv](uart.commit.csv) | time_ps十进制、PC/inst/a0/flags/cause/mem_addr十六进制；flags位exception=1/mem_valid=2/write=4/MMIO=8 |
| [uart.uart.csv](uart.uart.csv) | time_ps、write、寄存器offset、data，均十进制；取实际UART `reg_we/reg_re`，不是CPU intent |
| [faults.exceptions.csv](faults.exceptions.csv) | 从完整commit中仅筛出exception行，列同commit；独立地址/cause/响应预期见[faults-expected.json](faults-expected.json)，另有一次取指cause1 |

ebreak 的 AR 握手355ns，R握手395ns、数据`0x00100073`，提交445ns。UART 实际写THR的strobe在4375ns、data=65；此前offset0的data=1写发生于DLAB=1，属于DLL而非发送。最后一次LSR在6505ns读到96（THRE|TEMT），退出前串行解码已得到`A`。

## 误用防护与边界

负例包括空镜像、4097B MROM、缺失文件、无限循环timeout、a0非零ebreak，均按预期非零退出。guard随机测试seed27；28个显式case覆盖本地错误与正常转发、AW/W顺序、背压，另外验证下游错误与7种复位终止后的恢复。

S2 没有提供 AM/linker/data-bss/DiffTest、Flash/PSRAM启动、timer IRQ、系统随机延迟回归或综合结果。这些仍分别属于 S3–S7。当前无阻塞；ysyxSoC fork与主仓库改动尚未暂存/提交，嵌套Rocket Chip没有本步新增修改。
