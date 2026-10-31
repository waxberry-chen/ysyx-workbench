# S0：接口、模式与比较输入

> 2026-10-31；S0 完成。代码起点 `a7f40008f26dc28b6592fd55330e3a8e2d9a123d`，在已有规划文档及 `ysyx_soc_cpu.sv` 注释改动上实施；不修改 ysyxSoC 子模块。后续代码身份以运行 manifest 的逐文件 SHA-256 为准，不能只引用这个起点 commit。

**冷启动**：每个程序开始时共同复位 CPU 和预测器，不沿用上一个程序的历史。**OFF**：关闭预测但运行同一份新源码／观察逻辑，用于隔离预测增量。**提交历史**：只记录已经成为架构事实的条件分支结果，错误路径无需回滚历史。

## 1. 固定的实现合同

| 项目 | 实施值与边界 |
| --- | --- |
| `BPU_MODE` | 0=OFF，1=JAL_ONLY，2=GSHARE；当前 RTL 默认候选为 2 |
| `BPU_INDEX_BITS` | 默认 7；128 项二位二进制饱和计数器、7-bit GHR |
| PC hash | `PC[8:2] XOR GHR`；支持 RV32E 的 4 字节指令，不实现 C 扩展 |
| reset | PHT=01，GHR=0；trap/IRQ/MRET 保留已提交历史 |
| 查询边界 | IFU 的正常响应被接收时；地址取 `request_pc_q` |
| 同拍查询／训练 | 接收 metadata 使用边沿前 PHT/GHR；训练写入边沿后生效 |
| 保存内容 | 预测方向、预测 NPC、是否为有效条件分支查询、查询时 index |
| 训练 | GSHARE 下正常提交的合法条件分支；按保存 index 更新**当前**表项 |
| 恢复 | B/J 的真实 NPC 与保存 NPC 比较；JALR、trap、IRQ、MRET 保留既有恢复 |
| 接口 | CPU 外部 61-pin ABI 不变，单 outstanding 不变；新信号只在 core 内部 |

模式通过 `ysyx_25030087 → ysyx_soc_cpu → ysyx_core_axi4 → ysyx_core` 的参数传递。`make -C npc soc-build BPU_MODE=0|1|2` 给 wrapper 设置 `NPC_BPU_MODE` 宏；未设置宏时默认 2。直接例化内部模块的 testbench 可覆盖参数，历史 IFU/EXU 定向测试显式选 0。

OFF 保留原先“taken branch/JAL/JALR 一律 redirect”的行为，包括目标等于 PC+4。JAL_ONLY 和 GSHARE 共用 NPC 比较恢复；因此 OFF→JAL_ONLY 的差值包含这部分冗余恢复消除，不能全部归因于 JAL。

### 已核对的对齐边界

M5 没有完整实现 taken branch/JAL/JALR 的 instruction-address-misaligned 异常，取指 adapter 对 4 字节对齐有断言。此次 predecode **不提前预测到非 4 字节对齐目标**，不把目标低位强行清零；实际执行走到该非法对齐目标时仍沿用 M5 的限制。合法不跳转分支即使编码了半字对齐目标也不能被预测成一个触发总线断言的访问。完整 misaligned control-transfer trap 是已有 ISA 待办，不将其声称为此次支持范围。

## 2. 六个固定输入与 OFF 复现

输入直接使用 [M5 比较清单](../5-ysyx-soc-integration/s8-validation/comparison-inputs.json) 的 `.bin`，逐一核对 hash，不重新编译来改变工作量。先用 M5 S8 冻结仿真器复现，再用新源码 OFF 重新测量；六项 cycles/commits 和去掉时间戳后的完整 commit trace 一致。DiffTest 与终态 SRAM/PSRAM 比较开启。

| 程序 | 布局 | M5 与新 OFF cycles | commits |
| --- | --- | ---: | ---: |
| micro-sieve | MROM/SRAM | 186362 | 9688 |
| micro-fib | MROM/SRAM | 1633239 | 94717 |
| cpu-if-else | Flash/PSRAM | 489253 | 1521 |
| cpu-recursion | Flash/PSRAM | 1620552 | 9030 |
| cpu-bubble-sort | Flash/PSRAM | 842230 | 4154 |
| cpu-quick-sort | Flash/PSRAM | 1558810 | 6416 |

历史复现产物：`npc/build/gshare-bpu/legacy/`；三模式复测及源码／二进制／输入 hash：`npc/build/gshare-bpu/performance/`。可维护的重跑入口是 [bpu_performance.py](../../../../npc/tests/bpu_performance.py)，它拒绝镜像 hash、OFF 周期或跨模式提交序列不一致。历史 trace 存在时额外比较；新的三模式 trace 比较始终执行。

## 3. 测量口径与回归选择

Harness 时钟沿用 M5 的 100 MHz；DC/PT 另沿用 5 ns（200 MHz）预算。这里比较同一仿真环境的周期数，不把两种频率的墙钟时间混合比较。

cycles 沿用 M5 的全程口径（包含 reset/启动）；六程序禁用随机 AXI delay，无 IRQ，PHT 每次冷启动，启动代码参与训练。方向错误、NPC 错误、redirect 分类分别计数。观察细节见 [S2](2-integration.md)，结果见 [S4](4-performance-ppa.md)。

GSHARE 候选运行新增单元、错误路径定向、M5 S3/S4/S5/S6 的适用检查；其中 S6 包含 S1 协议／ISA、真实 SoC guard、CPU tests、随机等待、UART、RT-Thread。OFF 保留固定六程序、错误路径及 IRQ 对照。S8 不整套重跑冻结 checkout：它服务于上一阶段冻结，当前以独立输出目录、实际新二进制与 manifest 留证。完整 EDA 对照仍需服务器执行。
