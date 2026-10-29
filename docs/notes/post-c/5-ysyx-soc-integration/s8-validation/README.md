# S8 证据：干净功能构建、入口修复与补测

2026-10-30：**M18 通过，无未处置阻塞。** 采用干净工作区的已完成测试，加 ISA 入口修复后的受影响组复测。[review.json](review.json) 是汇总审查结果；原始失败 manifest 全部保留。没有执行 DC/PT，S7 沿用既有 cap90。

## 1. 实际执行顺序与版本

| 运行 | 结果与处置 | 原始记录 |
| --- | --- | --- |
| `npc/build/m5-s8` | 重新生成/ABI 通过；ccache 写沙箱外临时目录失败 | [manifest](attempts/m5-s8/manifest.json)、[日志](attempts/m5-s8/simulators-and-reference.log) |
| `npc/build/m5-s8-repro` | 构建/S2 通过；S3 microbench 缺 benchmark.h，入口漏克隆独立 am-kernels | [manifest](attempts/m5-s8-repro/manifest.json)、[日志](attempts/m5-s8-repro/s3-runtime.log) |
| `npc/build/m5-s8-final` | 补齐依赖、关闭 C/C++ 缓存，从空目录重建。前 10 步通过；S6 前三组通过后，regression 的 ISA runner 查找旧 S1 二进制失败 | [manifest](manifest.json)、[完整阶段日志](logs/)、[S6 原始 manifest](results/m5-s6/manifest.json)、[失败日志](continuation/initial-isa-contract-failure.log) |
| `npc/build/m5-s8-continuation` | 修复两个测试组织脚本，补跑 S6 regression 和 flow-local，全部通过 | [manifest](continuation/manifest.json)、[修复补丁](continuation/test-runner-fix.patch)、[回归日志](continuation/s6-regression.log)、[flow 日志](continuation/flow-local.log) |

修复说明见 [S8 实施记录](../8-reproduction-handoff.md#干净回归暴露的旧可执行文件依赖)。续跑只改变 `m5_s1_test.py` 和 `isa_contract_test.py`；其余原 S6 manifest 中的源码 hash 全部保持相同。旧 `m5-s1/cpu` 文件始终不存在，ISA 使用实际新构建的 `m5-s6/cpu/Vaxi4_cpu_test_top`，路径/hash 见 [cpu-executable.json](results/isa-contract-test/cpu-executable.json)。两 seed 各 97 个非法编码异常及合法指令检查通过。

源码为主仓库 `6023de4` 加 [S8 入口补丁](patches/root.patch)、上述测试路径修复；新增 S8 runner 的 hash 单独记录。ysyxSoC `2d365297`、Rocket Chip `d0c6b50f` 加 [既定接口补丁](patches/ysyxSoC__rocket-chip.patch)，独立 am-kernels `9804c83`、RT-Thread `bce7f1d`；完整 SHA/递归依赖在 manifest。

Java 17.0.20.1，仓库固定 Mill 0.12.4，firtool 1.105.0；Verilator/RISC-V GCC/Python 版本在 S6 manifest，firtool 二进制 hash 在主 manifest。下载依赖和安装工具复用，设计生成 RTL、Mill `out/`、仿真器、ref、AM 库与镜像重新构建。生成 SoC 去除注释/空白后与原文本一致；61-port 和补丁检查见 [契约 manifest](results/m5-s0/contract-check/manifest.json)。

## 2. 实际结果

| 测试来源 | 正向 SoC 运行 | 开启差分的提交数 | IRQ 差分数 | 预期失败检查 |
| --- | ---: | ---: | ---: | ---: |
| S2 最小启动/端点/真实错误 | 4 | — | — | 5 |
| S3 MROM/SRAM、启动与差分 | 31 | 363861 | 0 | 5 |
| S4 Flash 启动/容量 | 3 | 367650 | 0 | 9 |
| S5 timer/AM/RTT tick | 6 | 139556 | 17 | 2 |
| S6 四组系统/协议/CPU 回归 | 68 | 1824241 | 30 | 10 |
| **合计** | **112** | **2695308** | **47** | **31** |

这是按阶段计的运行次数，含不同配置下重复执行的程序；不是 112 个互不重复的程序。108 次 SoC 运行启用差分，全部提交/IRQ 匹配并比较最终 SRAM、PSRAM；S2 的 4 次保留独立预期及总线/串行检查。构建命令不计为 workload。

另有 primitive/IFU/LSU/EXU/CSR/译码测试、独立 AXI/guard 检查、10 seed 的 IRQ 等待及三种延迟通道单测。flow 本地 **56 项测试**、Tcl/SDC 契约及四种宏配置 scope 展开通过；这些不等于重新运行商业 EDA。

S6 的前 27 次运行来自主运行已完成的 RTT、UART、random 组；后 41 次来自修复后 regression。机器可读汇总为 [s6-workloads.json](s6-workloads.json)、[s6-images.json](s6-images.json)，两份原始来源为 [主运行 manifest](results/m5-s6/manifest.json)和[regression manifest](results/m5-s6/manifest-regression.json)。重复的协议负例按名称归并到最后通过的检查，不双重计数。

- 34 个适用 CPU tests 全部通过；`unalign` 按项目异常契约排除，[分类](results/m5-s6/cpu-tests.json)。
- RTT 正常/随机等待均 15 IRQ；六轮双线程进展、各方向 5 次切换、10 次 IRQ 内切换；sleep 4/6 tick 后于 4/7 tick 恢复。heap 总量4080384 B，峰值544 B并归零；最大观测 SP 使用仍为主栈/worker0/worker1/idle =224/448/372/268 B。[正常日志](results/m5-s6/rtthread-normal.tx)、[随机等待日志](results/m5-s6/rtthread-delayed.tx)。
- UART 在三种时序下各精确接收528字节；错误波特率负例有效。[实际串行帧](results/m5-s6/uart-normal.serial.csv)。
- 相对 S6 历史归档，仅两个 RTT 运行的提交/周期变化，分别多86条提交；其余66个运行的这些计数相同。构建路径字符串进入镜像，RTT 又包含按时间调度的循环，因此保存本次实际镜像和结果。S5 tick 的 +64 B/+160 条实例有完整布局与启动循环解释，见 [S8](../8-reproduction-handoff.md#一个实际差异源码相同镜像大小为何改变)。

四种真实 SoC 仿真器的构建告警合计为 PINCONNECTEMPTY 104、DECLFILENAME 24、DEFPARAM 8、UNUSEDSIGNAL 496、UNUSEDPARAM 4、BLKSEQ 64，完整上下文在 [构建日志](logs/simulators-and-reference.log)。构建保留端口/宽度/latch/环/未驱动等硬门禁；本页没有将上游/模型的全部告警称为消除。

## 3. 后续比较输入、波形与负例

固定程序使用 `SOC_DELAY=0`、100 MHz 仿真、冷启动；全程周期包括 reset 和启动。定义见 [比较合同](../comparison-contract.md)，实际参数、镜像布局和 ELF/BIN hash 见 [comparison-inputs.json](comparison-inputs.json)。

| 程序 | 布局 | cycles | commits |
| --- | --- | ---: | ---: |
| micro-sieve | MROM/SRAM | 186362 | 9688 |
| micro-fib | MROM/SRAM | 1633239 | 94717 |
| cpu-if-else | Flash→PSRAM | 489253 | 1521 |
| cpu-recursion | Flash→PSRAM | 1620552 | 9030 |
| cpu-bubble-sort | Flash→PSRAM | 842230 | 4154 |
| cpu-quick-sort | Flash→PSRAM | 1558810 | 6416 |

精选大件另存于 **`artifacts/m5-s8-20261030/`**，不随 `npc/build` 清理；该目录被 Git 忽略，移机时应一并复制或按源码重新生成，不能只复制本文链接。17 份 ELF/BIN/FST 的路径、大小和 hash 在 [artifacts.json](artifacts.json)。

| 波形 | 建议观察 |
| --- | --- |
| `waveforms/m5-s2/ebreak.fst` | reset 保持/延后释放、首个 MROM 取指、提交并退出 |
| `waveforms/m5-s2/uart.fst` | 窄写地址/lane、UART 寄存器访问、真实 TX 串行帧 |
| `waveforms/m5-s2/faults.fst` | 非法/只读/禁用地址访问、错误响应和精确 trap |
| `waveforms/m5-s5/latency-1.fst` | LSU pending、IRQ 接受、handler/MRET、前端 redirect/旧响应 |
| `waveforms/m5-s6/memory-1.fst` | 可控 responder 中的访存等待和副作用计数 |

可直接阅读的负例包括 [缺 data copy](results/m5-s3/missing-data-copy.log)、[缺 bss clear](results/m5-s3/missing-bss-clear.log)、[IRQ EPC 扰动](results/m5-s5/irq-epc-negative.log)、[缺 t0 恢复](results/m5-s5/context-negative.log)、[错误 RID](results/m5-s6/arbiter-bad-rid.log)、[错误波特率](results/m5-s6/uart-wrong-baud.log)、[过小栈边界](results/m5-s6/stack-bound-negative.log)。它们应失败，测试脚本据此确认检查机制有效。

## 4. S7 复用与归档核对

重新核对 S7 的72份原始归档；21份 RTL/include 中20份逐字节相同、CSR 仅注释差异，19份 flow 输入相同。具体 hash 在 [review.json](review.json)。本次不读取服务器工艺库或重跑 DC/PT，保留原 S7 人工审查及 leakage/reset 边界。

[archive.json](archive.json)登记203份原始文本/JSON/日志及其来源/hash；review、合并后的 S6 汇总和比较输入是本次派生材料，单独命名。最终范围、例外与后续 JOB-PREP-01 入口见 [M5 总验收](../signoff.md)。
