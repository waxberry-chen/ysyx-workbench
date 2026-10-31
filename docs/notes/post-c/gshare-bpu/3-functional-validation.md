# S3：系统功能验收与错误路径检查

> 2026-10-31：本地功能验收通过。记录功能检查的方法、分层位置和证据入口；整体阶段仍待服务器 PPA，见 [阶段状态](signoff.md)。

**错误路径**：预测错误后取到、但不应成为架构事实的指令。**定向测试**：人为构造某种边界，检查具体预期；与随机延迟测试互补。**负例**：故意注入错误，预期检查器报告指定失败；退出码非零本身不算证据。**回归**：重新运行原来已经成立的功能合同，检查新增预测没有破坏它。

## 1. 本次新实现与复用的边界

| 层次 | 此次修改／使用位置 | 要解决的问题 |
| --- | --- | --- |
| RTL | IFU/predecode/GShare/opbuf/EXU/core，见 [S1](1-predictor.md)、[S2](2-integration.md) | 预测、随指令保存、真实执行恢复、仅提交训练 |
| 仿真观察 | `npc/sim/bpu_monitor.sv`、`npc/csrc/soc/bpu_stats.h` | 记录预测事件，明确测试是否真正经过需要覆盖的方向组合 |
| 新测试 | [bpu/](../../../../npc/tests/bpu)、[bpu_test.py](../../../../npc/tests/bpu_test.py)、[bpu_system.py](../../../../npc/tests/bpu_system.py) | 单元模型、IFU 事务 scoreboard、EXU 恢复、错误路径副作用 |
| 原有验证 | `m5_s3_test.py`～`m5_s6_test.py`，S6 继续调用 S1 协议／ISA 测试 | 实际 SoC、存储控制器、随机 AXI delay、异常、中断和 RTOS |
| NEMU、AM、外围 RTL | 本次无功能改动，继续作为同一参考行为／启动软件／真实总线环境 | 不通过改变软件或参考模型来迁就预测器 |

## 2. 新增错误路径定向：如何让一个“必不跳转”分支被预测 taken

源码：[wrong-path.S](../../../../npc/tests/bpu/wrong-path.S)。先在 PC `0x20000020` 的循环分支训练 39 次 taken、1 次 not-taken。循环稳定后训练到强 taken（3）的 PHT 项为 `8 XOR 127 = 119`；退出的 not-taken 将该项减到弱 taken（2），GHR=126。

在 `0x20000224` 放置 `bne x0,x0,...`，它的 PC 索引为 9，`9 XOR 126` 也等于 119。它必不跳转，但应命中仍预测 taken 的项，产生一次受控误预测；两处之间的 JAL 不改变 GHR。

五个镜像只改变错误目标内容：store、CSR 写、非法指令、另一条 branch、未映射取指目标。正确路径检查 sentinel 内存和 mtvec 未被错误路径改变，最终 `a0=0`；同时检查异常数为零，DiffTest／终态内存一致，实际提交条件分支恰好 43 条，GSHARE 恰好训练 43 次。OFF/GSHARE 都运行，OFF 不训练，GSHARE 必须有 predicted-T / actual-NT 事件。补测还从 bus trace 确认 victim 的错误目标恰好被请求一次、响应被消费，取指错误版确实返回 SLVERR/DECERR；同时 AW/W/B 均只有初始化 sentinel 的一笔，排除错误路径 store。另用原 timer trap 程序做 OFF/GSHARE 对照，两模式均完成 2 次 IRQ 和 1 次同步异常。

取指错误版本最初用绝对地址书写 branch，GNU assembler 将它展开为“反向 branch + JAL”，使 victim 不再是预期编码，测试未达到方向覆盖而失败。改为显式机器编码并检查反汇编，使 `0x20000224` 保持 BNE、目标为 `0x20001000`。这不是修改 DUT 来绕过失败，而是修正测试刺激与声明的不一致。

## 3. 局部验证覆盖

`make -C npc bpu-test`：

- 1858 个预译码检查，覆盖合法／非法 RV32E 寄存器范围、B/J 偏移和取指 error。
- N=7、N=3 各 20000 次 PHT/GHR 模型事件，四计数器状态、饱和、别名和同拍读写。
- IFU 30000 拍，5628 次请求、1311 次 redirect、812 次旧响应丢弃；另有 234 次 redirect+response、67 次连续 redirect、576 次非空队列 flush、416 次队列同时出入、1865 次有效响应携带半字对齐目标。最后一类验证“不提前预测到非法对齐地址”，不是支持 C 扩展。
- EXU 方向四组合、offset=4、JAL link、JALR、trap/MRET 强制恢复及 IRQ 抢先分支。
- 两项预期失败检查：错误 index metadata 报精确 scoreboard 错误；移除误预测恢复的 mutant 报 taken branch redirect 错误。

历史 IFU/EXU 定向也在 OFF 下通过，新的源码依赖和训练端口已补齐，没有把新增 unconnected 输入作为宽泛 warning 豁免。

## 4. 真实系统回归的阅读顺序

入口：`make -C npc bpu-system`。先构建当前 GSHARE 的 MROM/Flash × 正常/随机延迟四个仿真器及 OFF MROM 对照，再运行新定向与原有 suites。完整产物隔离在 `npc/build/gshare-bpu/system/`，不覆盖 M5 归档。

1. `system/s3/`：MROM/SRAM 启动、data-copy/bss-clear、poison 与启动负例、DiffTest 注入、异常和固定 CPU 子集。背景见 [M5 S3](../5-ysyx-soc-integration/3-runtime-difftest.md)。
2. `system/s4/`：SPI、PSRAM、XIP、Flash→SRAM/PSRAM 布局、存储错误、完整适用 CPU tests、RT-Thread cooperative 容量 case。背景见 [M5 S4](../5-ysyx-soc-integration/4-boot-memory.md)。
3. `system/s5/`：CLINT 寄存器、IRQ mask/优先级/EPC、AM context 保存恢复、三种布局 timer、中断负例、RT-Thread tick，以及 10 个随机等待 seed 下的访存／IRQ 边界。背景见 [M5 S5](../5-ysyx-soc-integration/5-timer-interrupt.md)。
4. `system/s6/`：真实抢占／睡眠唤醒与资源检查、串行 UART 正负例、AXI 随机 delay seeds 1～10 与固定延迟、S1/ISA/guard 以及 CPU／存储回归。具体 workload 阅读 [M5 S6 validation](../5-ysyx-soc-integration/s6-validation/README.md)，本轮保存新的日志与 summary。

原有 `unalign` workload 仍按 ISA 合同排除，独立 misaligned data trap 测试继续运行。MROM 放不下的程序保留容量分类，并在 Flash/PSRAM 阶段运行；不能把容量排除解释为所有 CPU tests 均在 MROM 中通过。

## 5. 本地综合输入检查

`make -C npc/flow check test scope-check`：默认及两份对照配置的 SDC/source closure 检查、57 个 flow mock 测试、三模式 × 四宏 profile 均通过。新增 GShare/predecode 纳入 22-source closure；不存在通过移除预测逻辑来让综合 lint 通过的路径。真实面积／时序仍见 [S4 待办](4-performance-ppa.md#3-服务器面积时序对照)。

## 6. 实际结果与统计边界

完整命令 `python3 npc/tests/bpu_system.py --full` 正常结束，末尾为 `S6 all: PASS`、`BPU_SYSTEM full PASS`；随后新增的总线目标／错误响应检查与 OFF/GSHARE IRQ 对照完成定向补测。以下按实际 summary 文件去重计数，不把编译命令当作测试运行。

| 复用 suite | 真实 SoC 正向运行 | 差分提交 | IRQ | 预期失败检查 |
| --- | ---: | ---: | ---: | ---: |
| M5 S3 | 31 | 363906 | 0 | 5 |
| M5 S4 | 41 | 969321 | 0 | 9 |
| M5 S5 | 6 | 146225 | 17 | 2 |
| M5 S6 | 68 | 1892675 | 30 | 10 |
| 合计 | 146 | 3372127 | 47 | 26 |

全部正向运行均确认实际 `bpu.mode=2`，开启 DiffTest、完成 SRAM/PSRAM 终态比较，训练数=有效 metadata 数=正常提交分支数，未分类 redirect=0。表外还包括独立 S1 协议／CPU responder／ISA 检查、S5 的 10-seed LSU/IRQ 延迟检查，以及 12 次新增真实 SoC 定向（5 类错误路径 × 2 模式 + IRQ × 2 模式）。[18 次三模式性能比较](4-performance-ppa.md)单列，不并入此表。

S3 CPU 清单：24 PASS、1 容量排除、10 不在该阶段固定子集；S4/S6：34 PASS、`unalign` 按原合同排除。M5 S8 的冻结 checkout 发布流程未重跑；其所依赖的适用功能由上述新构建／当前 DUT 检查覆盖。

RT-Thread 正常／随机延迟版本各完成 15 次 IRQ，均通过抢占进展、睡眠唤醒、堆恢复及四个栈区域检查。IRQ/RTOS 的动态工作量会随时间改变，因此不将它们的提交数或周期变化作为固定工作量性能收益。

原始结果及源码／二进制追溯见 [system-summary.json](validation/system-summary.json)、[system-manifest.json](validation/system-manifest.json)、[system.log](validation/system.log)，新定向见 [targeted.json](validation/targeted.json)。初次串行调用旧 helpers 时部分 `results.json` 继承了上一阶段记录，保留原始文件；上表按各目录实际 summary 去重。维护的 `bpu_system.py` 现已在各阶段之间清空记录容器，避免下次复现重复记账，不改变测试判断。
