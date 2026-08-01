# 一生一芯 2306 讲义大纲

> 本文件对应 `docs/source/ysyx/docs/2306/index.md` 及其 `preliminary/`、`basic/`、`advanced/` 目录。时间为原课程给出的中等基础学习者预估小时数；零基础通常需要预估值的 2--3 倍。每一项的详细任务和最终验收以对应原讲义为准。

## 课程主线

目标是从程序、指令集、RTL、仿真、操作系统到 SoC 和流片，逐层构建一台可运行真实软件的 RISC-V 流水线处理器。学习过程中持续训练四种能力：读规范（RTFM）、查资料（STFW）、读代码（RTFSC）、用测试和调试工具定位问题。

```text
预学习 -> PA1 -> C1/NEMU -> C2/RTL -> C3/运行时
        -> C4/单周期NPC -> C5/IO -> C6/异常与RT-Thread
        -> B1/总线 -> B2/SoC -> B3/缓存优化 -> B4/流水线 -> B5/流片考核
        -> A/系统软件、ISA扩展与微结构优化
```

## 预学习阶段

目标：具备 Linux、C、数字电路、Verilator 和 NEMU/PA1 的最低工作能力，完成后申请入学答辩。每日学习记录贯穿全程。

| 顺序 | 任务 | 预估 | 对应讲义 |
| --- | --- | ---: | --- |
| 0 | 如何科学地提问 | 2 h | [preliminary/0.1](../source/ysyx/docs/2306/preliminary/0.1.md) |
| 1 | Linux 系统安装和基本使用 | 10 h | [preliminary/0.2](../source/ysyx/docs/2306/preliminary/0.2.md) |
| 2 | 计算机系统的状态机模型（课件/视频） | 2 h | [课程主页](../source/ysyx/docs/2306/index.md) |
| 3 | 复习 C 语言 | 20 h | [preliminary/0.3](../source/ysyx/docs/2306/preliminary/0.3.md) |
| 4 | 程序的执行和模拟器（课件/视频） | 2 h | [课程主页](../source/ysyx/docs/2306/index.md) |
| 5 | 搭建 Verilator 仿真环境 | 5 h | [preliminary/0.4](../source/ysyx/docs/2306/preliminary/0.4.md) |
| 6 | 数字电路基础实验 | 20 h | [preliminary/0.5](../source/ysyx/docs/2306/preliminary/0.5.md) |
| 7 | 完成 PA1 | 30 h | [preliminary/0.6](../source/ysyx/docs/2306/preliminary/0.6.md) |
| 8 | 撰写读后感、完成清单并申请入学答辩 | -- | [preliminary/0.7](../source/ysyx/docs/2306/preliminary/0.7.md) |

**预学习出口：** 通识问卷达到 100 分；Linux 与框架可用；Verilator/NVBoard 示例通过；数字电路和 C 语言必做题完成；PA1 到讲义结束提示；完成不少于 800 字读后感及每日学习记录；提交答辩申请。

## 基础阶段（C/B）

目标：先用 NEMU 理解 RV32IM，再把理解迁移到 RTL，最终在自己设计的流水线处理器上运行红白机游戏并接入 SoC。

| 顺序 | 任务 | 预估 | 对应讲义 | 主要产出 |
| --- | --- | ---: | --- | --- |
| C1 | 支持 RV32IM 的 NEMU | 10 h | [basic/1.1](../source/ysyx/docs/2306/basic/1.1.md) | 可执行 RV32IM 程序的模拟器与调试基础设施 |
| C2 | 用 RTL 实现最简单的处理器 | 5 h | [basic/1.2](../source/ysyx/docs/2306/basic/1.2.md) | NPC 第一条指令、基本取指/执行/停机 |
| C3 | 运行时环境和基础设施 | 5 h | [basic/1.3](../source/ysyx/docs/2306/basic/1.3.md) | AM 运行时、测试与跟踪工具 |
| C4 | 支持 RV32E 的单周期 NPC | 10 h | [basic/1.4](../source/ysyx/docs/2306/basic/1.4.md) | RV32E 单周期处理器 |
| C5 | 设备和输入输出 | 10 h | [basic/1.5](../source/ysyx/docs/2306/basic/1.5.md) | 串口、时钟、键盘、VGA 等设备 |
| C6 | 异常处理和 RT-Thread | 15 h | [basic/1.6](../source/ysyx/docs/2306/basic/1.6.md) | NEMU/NPC 上运行 RT-Thread |
| B1 | 总线 | 10 h | [basic/1.7](../source/ysyx/docs/2306/basic/1.7.md) | 处理器与存储器/设备的总线协议 |
| B2 | SoC 计算机系统（上、下） | 30 h | [basic/1.8](../source/ysyx/docs/2306/basic/1.8.md) | ysyxSoC、存储器和外设接入 |
| B3 | 性能优化和简易缓存 | 20 h | [basic/1.9](../source/ysyx/docs/2306/basic/1.9.md) | 性能测量、瓶颈分析、cache 与形式化验证 |
| B4 | 流水线处理器 | 20 h | [basic/1.10](../source/ysyx/docs/2306/basic/1.10.md) | 流水线、冒险处理、`fence.i` |
| B5 | B 阶段流片准备与考核 | -- | [basic/1.11](../source/ysyx/docs/2306/basic/1.11.md) | 流片前检查、代码调试考核与申请 |

### 基础阶段的能力依赖

1. C1 先建立 ISA、程序执行和调试器认知，避免直接在 RTL 中猜指令行为。
2. C2--C4 保持“先单条指令、再最小程序、再完整 ISA”的增量路径；每次新增功能都做回归。
3. C5--C6 将地址空间、设备、异常和操作系统连接起来，不能只以“游戏能启动”作为正确性证明。
4. B1--B4 以协议、时序和性能数据为依据；优化前先建立可重复的基线。

## 进阶阶段（A）

2306 版本只提供方向性大纲，后续细节和必做顺序可能调整；参与考核或流片时以最新版讲义为准。

建议顺序遵循“先完成、后完美”：先做软硬件共同依赖的 ISA 功能，再扩展系统软件，最后用完整软件评估微结构优化。

| 方向 | 任务/主题 | 对应资料 |
| --- | --- | --- |
| ISA 与微结构 | RV32M 乘除法器；RV32E 改 RV32I；增大 I-cache | [advanced/2.1](../source/ysyx/docs/2306/advanced/2.1.md) |
| 系统软件 | PA3.2 用户程序与系统调用；PA3 文件系统与应用程序 | [advanced/advanced](../source/ysyx/docs/2306/advanced/advanced.md) |
| 虚存与特权 | 虚存管理；完整特权级；xv6 | 同上 |
| 操作系统 | 启动 Linux 和 Debian | 同上 |
| 性能 | 缓存进阶；分支预测 | 同上 |

## 专题与延伸

专家报告覆盖高性能处理器性能测算、乱序访存、昆明湖前端、乱序执行、缓存等主题；这些内容不是 2306 预学习或基础阶段的必做验收项。

## 全课程完成检查

- [ ] 每个阶段都有可复现的构建、测试和运行命令。
- [ ] 记录每次失败的现象、假设、验证和结论，而不是只保存最终代码。
- [ ] 处理器功能、软件栈和工具链均有分层测试；性能优化有优化前后的数据。
- [ ] 代码、Makefile、测试和提交记录保持可追踪；流片前按 B5 的最新版要求复核。
