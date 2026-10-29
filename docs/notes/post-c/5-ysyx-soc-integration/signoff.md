# M5 验收：真实 SoC 启动、系统验证与 CPU 子系统基线

> 2026-10-30：**M5 S0–S8 / M01–M18 在约定范围内验收通过，无未处置阻塞。** S8 干净构建暴露的测试入口依赖已修复并完成受影响组补测；沿用 S7 cap90，不重跑 DC/PT。

## 1. 最终实现与阅读入口

| 内容 | 当前行为 | 实现/学习入口 |
| --- | --- | --- |
| CPU 与外部接口 | RV32E 16 GPR、无 M/C；顺序提交；IFU/LSU 原生 AXI4 单拍、全局一笔外部 outstanding，保留 byte address/size/lane | [S1](1-axi4-interface.md)、`npc/vsrc/top/ysyx_25030087.sv`、`ysyx_soc_cpu.sv` |
| SoC 路由与设备 | 复用 ysyxSoC 互联、SRAM、UART 等；增加默认错误/权限保护，完善 SPI XIP 和 PSRAM 颗粒行为 | [S2](2-bringup.md)、[S4](4-boot-memory.md)，其中有逐层源码入口；上游完整 SoC 不作为个人原创实现 |
| 启动与内存 | MROM/SRAM、Flash→SRAM、Flash→PSRAM 三种布局；CPU 执行 poison、代码/data 搬运和 bss 清零；harness 只加载只读镜像 | [S3](3-runtime-difftest.md)、[S4](4-boot-memory.md)、[build/boot 阅读笔记](../../knowledge-notes/soc-build-and-boot-reading-notes.md) |
| 定时器中断 | 内部 CLINT mtime/mtimecmp、MTIP、CSR mask、精确 IRQ/MRET、AM 上下文与 RTT tick | [S5](5-timer-interrupt.md)；外部 IRQ 与 ChipLink/slave 保持关闭 |
| 系统验证 | 逐提交及 IRQ DiffTest、独立协议/异常预期、最终 RAM 检查；有限 RTT 抢占/阻塞唤醒、资源水位、实际 UART TX、随机 AXI 等待 | [S6](6-system-validation.md)、[S8](8-reproduction-handoff.md) |
| 可综合 CPU 子系统 | wrapper + core + adapters/arbiter/router/CLINT；TT / 5 ns 下面积和数据时序评估 | [S7 cap90 基线](s7-validation/baseline/README.md)；不包括完整 SoC 存储/外设 |

## 2. 验收矩阵的归并判断

具体通过条件仍以 [M01–M18 矩阵](test-plan.md)为准；本表给出最终证据入口，不改写早期阶段 manifest。

| 验收项 | 状态与证据 |
| --- | --- |
| M01–M02：依赖、生成、ABI、地址/reset/容量合同 | S0 已通过；S8 在新目录重新生成 SoC，61-port 与预期 Rocket Chip 补丁检查通过 |
| M03–M05：AXI 单拍/窄访问、背压、公平仲裁、旧响应/错误/reset | S1 已通过；S8 的 S6 全组回归重新运行独立事务 scoreboard、断言、CPU 故障及负例 |
| M06：最小启动、UART、真实默认错误 | S8 重新运行 S2，通过；UART 使用实际 serial TX 解码，错误有独立 cause 预期 |
| M07–M08：AM/SRAM、启动、DiffTest | S8 重新运行 S3，通过；31 个正向运行、启动存储覆盖、5 个负例/容量门禁 |
| M09–M10：Flash、PSRAM、容量 | S4 已通过；S8 的启动/容量组通过，SPI/PSRAM 和 34 项适用 CPU tests 由 S6 全组回归覆盖 |
| M11–M13：CLINT/CSR、精确 IRQ、AM Context | S8 重新运行 S5，通过；三种布局、6 个真实 SoC 正向运行/17 IRQ、10 个等待 seed 和上下文/EPC 负例 |
| M14–M16：有限 RTT、UART、系统随机等待/回归 | S6 历史验收通过；S8 全组复现结果见下节及归档 |
| M17：CPU 子系统面积、数据时序、电气与 coverage | 沿用 S7 人工审查结论；本次核验 72 份归档及源码/flow 对应关系，不运行 DC/PT |
| M18：干净功能复现与交接 | 通过；主运行已完成组 + 测试路径修复后的 regression/flow-local，来源/hash/负例/精选波形及比较条件已归档 |

## 3. S8 复现与证据

本次共 **112 个真实 SoC 正向运行**（按阶段计运行次数，含重复程序）；其中 108 次启用差分，共 **2,695,308 条提交、47 次 IRQ**，全部匹配并检查最终 RAM。31 项预期失败检查有效；34 个适用 CPU tests 通过，unalign 按异常契约排除。另有模块/协议、独立译码、10 seed IRQ 等待和 flow 本地检查；不把构建命令计为 workload。

干净构建目录为 `npc/build/m5-s8-final/`，补测记录在 `npc/build/m5-s8-continuation/`。入口：

```bash
make -C npc s8-test S8_ARGS="--out /绝对路径/新的S8目录"
```

该入口重新生成 SoC，构建四种仿真器、NEMU ref、AM 库和镜像，再执行 12 个步骤。源 checkout 中没有旧 `build/`、Mill `out/` 或 AM 编译库，C/C++ 编译缓存关闭。选取和覆盖关系见 [S8 实施记录](8-reproduction-handoff.md)，原始结果、版本/hash 和统计见 [S8 归档](s8-validation/README.md)。

主仓库输入为 `6023de4b94a4b88488d5877ac6ba711b97491760`，带已记录的 S8 Makefile/忽略规则修改；实际运行的新增组织脚本另记 hash。ysyxSoC 为 `2d365297e76661faeafb4059d3ed257d26fe8778`，Rocket Chip 为 `d0c6b50fdefcdbe121e9788433ea51f7efaf1d32` 加既定接口补丁；am-kernels 为 `9804c83061d595712c0aef75c513318576480315`，RT-Thread 为 `bce7f1d509b05e53022be89a719df077e89b507b`。全部递归依赖见 manifest。

主运行在 S6 regression 发现硬编码旧 ISA 可执行文件路径后停止。修复两个测试组织脚本并补跑 regression、flow-local；前三个 S6 组和此前步骤的结果保留。原 FAIL manifest 不改写，最终结论依据 [主运行与续跑证据](s8-validation/README.md)，不是把失败忽略或声称原运行一次全绿。

S8 没有修改功能 RTL、harness、NEMU、AM 或测试程序。当前 core 与 cap90 完全相同，CSR 只有注释差异，其余 19 份 RTL/include 与 19 份 flow 输入逐字节相同。`9912da3` 的声明顺序修复已经包含在 cap90 中。本次新文档/复现入口的提交不需要为已测硬件重新建立一份 PPA。

## 4. S7 面积/时序结论与例外

| 指标 | 基线 |
| --- | ---: |
| 时序约束点 | 5 ns / 200 MHz |
| 标准单元面积 | 9530.135856 library_area |
| PT 最差 setup / hold slack | +2.444726 / +0.009693 ns |
| 电气规则违例 | 0 |
| timing coverage | 9956 met、0 violated、9120 untested 已分类 |

条件为 TT / 0.9 V / 25°C、ideal clock、ZeroWireload 和冻结的 IO/uncertainty；DC 使用 Ultra、增量 DRC 和库输出最大电容 10% 裕量，PT 使用原始库独立检查。8958 个 reset 物理检查仍暂缓，162 个检查对应 81 个常量输出。

保留 DC 原始 `CONSTRAINT_FAIL` 与 PT `REVIEW_REQUIRED`：用户接受只记录 Ultra 自动 leakage 零目标，它不是本工程的功耗预算；未进行功耗验收，不为清空状态重新综合。具体告警、覆盖对象和路径审查见 [S7 原始基线](s7-validation/baseline/README.md)。M4 的 04/05 基线独立保留，不把不同 scope 的面积差称为优化收益。

## 5. 值得保留的定位案例

| 现象 | 原因/方法与证据 |
| --- | --- |
| 程序能被加载，但缺 copy/clear 应当失败 | CPU 先 poison SRAM，再分别把复制/清零 store 改为 NOP；软件自检通过非零 a0 暴露缺失，[S3 负例](s3-validation/README.md)及 S8 重跑日志 |
| 连续控制流修正可能丢失后续取指 | S5 修复连续 redirect 时对旧响应/缓冲状态的处理；IRQ、MRET、访存等待各有独立预期和 seed，[S5](5-timer-interrupt.md) |
| DiffTest 本身也需证明能报错 | 提交 GPR/IRQ EPC 扰动必须 mismatch；漏恢复 t0 由软件哨兵失败揭示；保存 S8 原始负例日志 |
| DC 电气通过，PT 最大电容违例 | 核对同一网表及接收电容口径，使用经过本库/本设计验证的 10% 裕量与增量修复，[S7](7-synthesis-sta.md) |
| 新目录构建缺 benchmark.h | `am-kernels` 是独立、被忽略的仓库；补齐依赖快照后重建，失败尝试保留，[S8](8-reproduction-handoff.md) |
| ISA 检查依赖旧 S1 二进制 | S6 已改变构建目录，ISA runner 却仍写死旧路径；改成显式 `--cpu-exe` 并记录 hash，在旧文件不存在时完成受影响组复测，[S8](8-reproduction-handoff.md#干净回归暴露的旧可执行文件依赖) |
| 相同源码重建后提交数略变 | `__FILE__` 路径字符串改变镜像和启动工作量；结合符号/布局/循环计算解释，[S8 实例](8-reproduction-handoff.md#一个实际差异源码相同镜像大小为何改变) |

## 6. 保留边界与下一步

- ISA/特权行为以项目契约为准；未声明完整 RISC-V compliance。无 C/M、MMU、cache、burst/multi-outstanding、PLIC 或外部中断。
- RT-Thread 是有限、可自动退出的验证 workload；UART RX、交互 shell/动态装载属于后期选项。PSRAM 路线已选，SDRAM、GPIO/PS2/VGA 等没有纳入本轮功能验收。
- 仿真里的 SRAM 是 RTL 数组，Flash/PSRAM 有行为模型与 C++ backing；没有 SRAM macro、完整 SoC PPA、实板或流片结论。
- 真实 reset 分发/释放/脉宽、多角/OCV、PnR/CTS/寄生、四值仿真、GLS/形式等价和功耗仍为后续工作；[reset TODO](../4-pre-soc-signoff/reset-timing-todo.md)继续有效。

下一步先制定限定 GShare 的设计与验收计划，沿用 [固定比较输入](comparison-contract.md)，再实施功能及同条件性能/面积/时序对照。该增量结束后阶段性冻结，执行 **[JOB-PREP-01：理解考察与简历 v1](../../output/interview-readiness.md)**，随后投递与回顾并行；不自动转入 M6 I-cache 或更多外设。
