# S1：预译码与 GShare 表

> 2026-10-31；单元验收通过。此文按“功能 → 实现位置 → 如何验证”阅读。

**别名（alias）**：不同的 PC/历史组合映射到同一个 PHT 项。**饱和计数器**：加到 3 不再增加，减到 0 不再减少。**查询／训练**：分别是读取预测和用真实结果调整预测状态。

## 1. 预译码：从指令取得类别与目标

新增 [ysyx_predecode.sv](../../../../npc/vsrc/core/ysyx_predecode.sv)。它识别六种合法 branch funct3、RV32E 的 rs1/rs2 范围，以及 JAL 的 rd 范围，拼接 B/J 立即数并符号扩展，计算 `request_pc + immediate`。取指响应带 error 时两种识别均为 false。

这部分只帮助前端选择下一地址。完整 IDU 仍负责非法指令等架构处理；预译码不接管 GPR 读取、不判断真实比较结果。`target` 对非预测指令没有功能意义，IFU 必须使用类别与错误位进行门控。

## 2. 方向预测：小寄存器表与提交历史

新增 [ysyx_gshare.sv](../../../../npc/vsrc/core/ysyx_gshare.sv)。`ghr_q` 是最近 N 个已提交分支的方向，最新一位移入 bit 0；PC 丢弃最低两位后取 N 位，与 GHR XOR，索引 `pht`。计数器 MSB 为方向。

PHT 每项有独立 reset／写使能。相同训练事件只写 `train_index` 对应的一项；所有项 reset 到 01。最初尝试在循环里 nonblocking reset 整个数组，当前 Verilator 5.008 对 128 项报 `BLKLOOPINIT`；改为 generate 展开的逐项时序块，保持异步 reset 及边沿更新语义，也明确了当前为寄存器实现。

取指到提交之间 GHR 可能变化，因此 `train_index` 来自该指令随身保存的查询索引。另一个分支可能已训练同一项，所以训练读取该项**此刻**的 counter 后加／减，而不携带旧 counter 回写。代码中不需要推测历史恢复或训练队列。

## 3. 验证证据

入口：`make -C npc bpu-test`；完整日志、命令与结果在 `npc/build/gshare-bpu/unit/`。

| 测试源码 | 验证方法 |
| --- | --- |
| [predecode.cpp](../../../../npc/tests/bpu/predecode.cpp) | 手工编码六类分支/JAL，正负／边界偏移，x0/x15/x16/x31，保留 funct3，普通指令与 error；检查类别和目标 |
| [predictor.cpp](../../../../npc/tests/bpu/predictor.cpp) | 独立 C++ 数组／history 模型；N=7、N=3 各 20000 事件，四状态与上下饱和、显式交替／两分支相关序列、别名、连续训练、同项读写、mid-run reset |
| [ifu.cpp](../../../../npc/tests/bpu/ifu.cpp) | 30000 拍外部接口 scoreboard，接收时计算期望 metadata；等待期间继续训练，验证旧上下文不会随新 GHR/PHT 改变 |

C++ 模型在时钟边沿前检查旧预测，边沿后按训练事件更新软件状态，再检查新预测。局部与系统接入的边界测试见 [S2](2-integration.md)、[S3](3-functional-validation.md)。没有用本轮性能去反推“128 项最优”；该参数仍是小规模首版选择。
