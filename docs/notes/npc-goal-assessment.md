# ysyx 目标可行性、范围与求职价值评估

> 评估日期：2026-08。本文评估 [ysyx-goal.md](./ysyx-goal.md) 的实现路径与取舍，不替代目标定义。工程进度变化后，应更新“当前基线”和工期估算。

## 1. 结论

目标总体可达成，且与 RTL/SoC 前端岗位高度匹配，但完整版本属于毕业设计级项目，超出讲义主线直接覆盖的范围。讲义能够支撑单周期核、异常/RTOS、AXI4-Lite SoC、I-cache、流水线和基本验证；D-cache、解耦前端、GShare/BTB 的恢复机制、PMP 及工业级验证仍需自行设计。

求职版本应优先形成完整闭环：

> RV32IM 顺序五级流水核 + M-mode 异常/中断 + AXI4-Lite SoC + SRAM/UART/CLINT + RT-Thread + I-cache + 可复现验证与 PPA 数据。

在此基础上，选择“解耦前端 + GShare/BTB”或“更完整的互联及协议验证”作为主要亮点。D-cache、A/F、U-mode 和 PMP 不应阻塞首个可展示版本。

## 2. 当前基线

目前已有 NEMU、AbstractMachine、RV32E 单周期 NPC、CPU 测试和 DiffTest，已建立 ISA 语义、软件运行环境和 RTL 差分调试基础。相对于最终目标，功能进度约为 15%--25%；这一阶段工作量占比不高，但它是后续集成和定位问题的关键基础。

当前最重要的正确性契约是：

- 以指令提交点定义架构状态和 DiffTest 时机；
- 区分组合计算、时钟沿状态更新与提交事件；
- 后续流水级、异常、访存响应和 flush 均携带对应指令的有效信息；
- 在引入性能优化前保留可重复的回归基线。

## 3. 讲义覆盖度

参考 [C 阶段](../lectures/ysyx/ysyx2306-c-stage.md)、[B 阶段](../lectures/ysyx/ysyx2306-b-stage.md) 和 [课程大纲](../lectures/ysyx/ysyx2306-outline.md)：

| 目标 | 讲义路径 | 覆盖判断 |
| --- | --- | --- |
| RV32 基本整数核 | C4、A 阶段 RV32E→RV32I/RV32M | 有基础，扩展需实现 |
| UART、Timer、MMIO | C5、B1、B2 | 充分 |
| CSR、异常、中断、RT-Thread | C6、B4 | 支撑最小 M-mode 系统，非完整特权规范 |
| AXI SoC 互联 | B1、B2 | 支撑 AXI4-Lite、仲裁、Xbar 和随机延迟，不等于完整 AXI/NoC |
| 五级流水线 | B4 | 覆盖 valid、stall、flush、forwarding 和精确异常 |
| I-cache | B3 | 有明确的简单直接映射实现路径 |
| D-cache | 无完整主线 | 需自行处理写策略、refill、MMIO bypass 和访存顺序 |
| 解耦前端 | B4 仅提供方向 | buffer、redirect、过期响应丢弃需自行设计 |
| GShare、BTB | B4/A 阶段仅作优化方向 | 预测器易实现，流水线恢复和验证较难 |
| DiffTest、随机测试、断言、形式验证 | C4、B1、B3、B4、B5 | 基础较好，未形成完整 UVM/coverage 流程 |
| PMP、U-mode、A/F | 基本未覆盖 | 作为远期扩展 |

因此，讲义能覆盖求职版目标的大部分知识路径，但不能直接给出完整实现。尤其要警惕把简单模块的局部实现误认为系统集成已经完成。

## 4. 主要难点

整体难度约为 8/10。难点主要来自机制之间的组合，而非单个模块：

1. 可变延迟取指/访存与流水线 backpressure；
2. redirect、flush、异常和中断的优先级及精确提交；
3. cache miss、store、MMIO 和总线响应的交互；
4. 分支预测错误时的在途请求、指令缓冲和 GHR 恢复；
5. RT-Thread、随机总线延迟、cache 和预测同时开启后的验证；
6. 功能正确之后的 lint、综合、STA、网表仿真和 PPA 权衡。

已有五级流水线设计经验可降低基础 hazard/forwarding 的学习成本，但无法消除上述集成工作。现成 GShare RTL 主要能帮助理解预测表逻辑；预测接口、更新时机、元数据传递及恢复仍应针对 NPC 重新设计。商业 RTL 若无明确授权，不应复制或派生到公开项目中。

## 5. 工作量估算

以下为有效开发时间，不含长时间中断后的恢复成本：

| 里程碑 | 估算 |
| --- | ---: |
| C5/C6：设备、CSR、异常、中断、RT-Thread | 50--90 h |
| B1/B2：AXI4-Lite、仲裁、随机延迟、SoC 集成 | 60--110 h |
| 五级流水线、冒险、flush、精确异常 | 100--180 h |
| 性能计数器和简单 I-cache | 50--90 h |
| 解耦前端、GShare、BTB 和错误恢复 | 70--140 h |
| D-cache | 70--150 h |
| 回归、断言、综合、STA 和文档 | 80--150 h |

完整目标约需 **400--750 h**：每周 15 h 约 7--12 个月，每周 25 h 约 4--7 个月。加入 A/F、U-mode、PMP 或 write-back D-cache 后可能达到 650--1000 h。

求职版 MVP 约需 **220--380 h**，适合先形成能够稳定运行、验证和量化的版本，再追加亮点。讲义中的课时是学习任务的理想估计，不宜直接作为独立设计和调试工期。

## 6. 推荐范围与顺序

### 6.1 必做

- RV32I；有余力再实现迭代式 M，暂缓 A/F；
- M-mode CSR、精确异常、Timer 中断和 RT-Thread；
- 五级流水线、valid/stall/flush、forwarding；
- AXI4-Lite master、interconnect、SRAM/UART/CLINT；
- 随机延迟和 backpressure；
- DiffTest、断言、自动回归和性能计数器；
- lint、综合、STA、面积与 Fmax 记录；
- 简单、可参数化的 I-cache。

### 6.2 选择一个主要亮点

- 偏 CPU 前端：小型 instruction buffer、GShare、BTB、预测恢复和收益分析；
- 偏 SoC/互联：多 master/slave、仲裁、公平性、错误响应、协议断言及带宽/延迟统计。

本项目的求职方向为 Frontend Design > Verification > Physical Design，建议以流水线 CPU 为主体，同时把 AXI 互联验证做深；若时间允许，再加入规模受控的 GShare/BTB。

### 6.3 延后

- D-cache，尤其是 write-back/write-allocate 方案；
- A/F、U-mode、PMP、MMU/Linux；
- 完整 AXI burst、一致性协议和复杂 NoC；
- 与目标岗位关联较弱的复杂显示、游戏和外设。

如果只实现 I-cache，应在文档和简历中明确写 `L1 I-cache`，不宣称已经实现完整的 L1 cache subsystem。

### 6.4 实施顺序

1. 在单周期 NPC 上完成 C5/C6 并启动 RT-Thread；
2. 定义统一的访存 request/response 契约并引入随机延迟；
3. 接入 AXI4-Lite、interconnect、SRAM/UART/CLINT；
4. 建立断言、回归和性能计数基线；
5. 改造五级流水线，先保守 stall，再逐步加入 forwarding；
6. 在流水线版本重跑 RT-Thread、DiffTest 和随机延迟回归；
7. 加入 I-cache 并处理 `fence.i`；
8. 加入 instruction buffer，明确 redirect 和过期响应处理；
9. 先测静态预测基线，再实现 GShare/BTB 并量化收益；
10. 所有主线稳定后再评估 D-cache。

## 7. 求职价值与证据

若工程具有可复现的“规格→RTL→验证→性能/PPA”闭环，预期价值为：RTL/SoC 前端 8--9/10，Design Verification 7--8/10，Physical Design 4--5/10。若只有功能列表而缺少验证、指标和设计取舍记录，价值会显著下降。

岗位需求快照表明，相关职位普遍重视微架构与 RTL、总线/互联、综合与时序、验证计划、随机测试、断言和形式验证：

- [Apple SoC RTL Design Engineer](https://jobs.apple.com/en-au/details/200626205-0157/soc-rtl-design-engineer?team=HRDWR)
- [NVIDIA SoC Design and Verification Intern](https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/SOC-Design-and-Verification-Intern---2026_JR2005802-1)
- [NVIDIA Custom SoC IP Verification Engineer](https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Custom-SOC-IP-Verification-Engineer_JR2020783)

为提高可展示性，应保留：

- 微架构文档：模块图、接口、流水级、hazard 矩阵、flush/异常优先级；
- verification plan、测试矩阵、自动回归、断言和覆盖结果；
- CPI/IPC、stall、cache hit/miss、预测准确率、面积和 Fmax 对比；
- 若干代表性 bug 的波形、首错、根因、修复和防回归措施；
- RT-Thread + UART + Timer 演示，以及随机 AXI backpressure 长时间回归；
- 可复现的构建命令、工具版本和 CI 结果。

若重点投递验证岗位，应额外为 AXI interconnect 或 cache 建立一个范围受控的 SystemVerilog/UVM 环境，包括 reference model/scoreboard、constrained-random、functional coverage 和协议断言。若重点投递前端岗位，则优先补齐综合约束、STA、PPA 对比和关键路径优化记录；Physical Design 只需完成基础后端流程认知，不宜挤占主体开发时间。
