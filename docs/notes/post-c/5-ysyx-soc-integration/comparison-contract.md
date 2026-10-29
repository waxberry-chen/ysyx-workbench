# M5 → 限定 GShare：固定比较输入

本页是 S8 的交接合同，不是预测器设计方案或收益结论。后续先写增量设计/验收计划，再实施；不同时改变流水线、cache、总线事务能力或外设配置。

**CPI** 是周期数除以已提交指令数；这里首先固定现有 harness 能直接复核的全程计数。**冷启动**指每次新建仿真实例并复位，不继承上次预测器或程序状态。**预测准确率**只统计实际发生预测且最终得到真实结果的对应分支；尚未实现的计数不能从 redirect 数直接推导。

## 1. 固定平台与程序

| 项目 | 固定条件 |
| --- | --- |
| CPU | RV32E、16 GPR、无 M/C；IFQ 深度 2；当前 AXI4 单拍、全局一笔外部 outstanding；内部 CLINT |
| 实际系统 | `ysyxSoCFull`、当前 SoC/递归依赖和补丁版本，见 [S8 manifest](s8-validation/manifest.json) |
| 存储 | 4 KiB MROM、8 KiB SRAM、16 MiB Flash backing、4 MiB PSRAM；保留真实 SPI/PSRAM 访问延迟，不换成零等待 RAM |
| 仿真 | 100 MHz，即 10 ns；共同 reset 20 周期及已有 CPU 释放链；每次冷启动；`SOC_DELAY=0`，关闭人为随机延迟 |
| 软件 | AM `ARCH=riscv32e-ysyxsoc`；当前 `-O2` 和既定 ISA/ABI 编译配置；保持 ELF/BIN hash，不在前后比较间重新选择优化选项 |
| 对照程序 | `micro-sieve`、`micro-fib` 使用 MROM/SRAM；`cpu-if-else`、`cpu-recursion`、`cpu-bubble-sort`、`cpu-quick-sort` 使用 Flash→PSRAM |
| 正确性 | 开 DiffTest；提交数与 diff_steps 相等，结束时完整 SRAM/PSRAM 比较；这六个程序不启用 IRQ，没有预期异常和 UART 输出 |

程序分别覆盖循环、递归及条件控制，也保留不同取指存储的影响。microbench 使用当前 fixture 的 **SIEVE_S / FIB_S smoke**，不是完整 benchmark 或评分。选定镜像、源、工具、实际参数和基线全程计数保存在 [comparison-inputs.json](s8-validation/comparison-inputs.json)。不挑选事后收益最大的程序替换这组输入；可以增加额外 workload，但应单独报告。

只固定源码 revision 还不够：C 的 `__FILE__` 可能把构建路径放入镜像。本次重建中 RT-Thread tick 镜像因此增加 64 B，启动多执行 160 条指令，见 [S8 实例](8-reproduction-handoff.md#一个实际差异源码相同镜像大小为何改变)。比较时使用保存的同一 BIN；若编译条件改变，先重新建立匹配的关闭预测器对照组。

## 2. 计数起止与比较方式

现有 [`npc/csrc/soc/main.cpp`](../../../../npc/csrc/soc/main.cpp) 的 `main()` 从仿真开始累计完整时钟周期，`npc_soc_commit()` 计数提交事件，正常 EBREAK 触发结束。冻结的原始 `cycles` 包括初始 reset、启动复制/清零及程序执行；`commits` 包括启动指令和最终 EBREAK。末个上升沿触发退出可能早于该周期的下降沿，沿用原计数，前后不补不同常数。

- 首先逐程序报告相同镜像的 `cycles`、`commits`、`cycles / commits` 以及 `cycles_before / cycles_after`。固定无 IRQ 的程序应有相同架构提交序列；不同周期不应改变程序结果。
- 该比值表示当前真实系统的**全程**效果，包含启动和存储等待。不能称为纯执行流水线 CPI，也不能把 `1 / 时序路径延迟` 直接当成程序加速比。
- 若后续要观察 `main` 内的预测效果，先实现统一的 commit-PC/测量区间计数，然后在**同一计数器实现**上重新运行关闭/开启预测器两组。明确测量开始/结束事件和训练是否计入；不拿本页全程数值与新局部区间比较。
- 预测器设计计划还须定义条件分支数、有效预测数、预测错误数和恢复代价；方向预测与目标供给分别说明。当前没有这组统计，因此本页不填写预测准确率。

RT-Thread、UART 和随机等待保留为正确性/鲁棒性回归：IRQ 到达和轮询次数随时间变化，会改变提交数。它们不加入这组固定指令流的性能对照。功能验收仍要求覆盖错误预测与 LSU 等待、旧响应、异常/IRQ、MRET、reset 的交互。

## 3. 面积/时序比较

沿用 [S7 cap90](s7-validation/baseline/README.md)：`ysyx_25030087` CPU 子系统 top、Flash PC、同一 filelist 范围，TT / 0.9 V / 25°C、同一 DB、5 ns / 200 MHz、ideal clock、ZeroWireload、相同 IO/uncertainty/reset 条件；DC Ultra、`-no_autoungroup`、增量 DRC、max fanout 32 和库输出最大电容 ×0.90 策略保持相同。新增预测器 RTL 应纳入这一 scope；新增存储如何映射也须说明。

基线面积 9530.135856 library_area，setup/hold slack +2.444726/+0.009693 ns。功耗未验收，reset 物理时序仍暂缓；保留泄漏零目标处置。若工具、库、SDC、编译策略发生改变，须同条件重测关闭预测器的对照组。本次 S8 按用户要求不重跑 DC/PT。

**200 MHz 是 EDA 约束点；100 MHz 是当前仿真时间标尺。** 预测器前后周期比较可在同一仿真时钟下进行；面积/时序是否仍达标由相同 5 ns 的 DC/PT 评估回答，两者不能混用。

## 4. 冻结后的待办

限定 GShare 验收后阶段性冻结，进入 [JOB-PREP-01](../../output/interview-readiness.md)：用自己的语言解释 CPU/SoC、启动、异常/中断、验证、PPA 与预测器取舍，定位证据并完成小变化，再整理简历 v1、开始投递。此待办保留在 roadmap 和总验收交接中，不会因测试 PASS 自动视为完成。
