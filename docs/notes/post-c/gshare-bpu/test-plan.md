# GShare BPU 验收矩阵与比较口径

> 2026-10-31；本文件保留验收设计；实际结果见 [单元与集成](2-integration.md)、[功能验证](3-functional-validation.md)、[性能／PPA](4-performance-ppa.md)。架构规则见 [plan.md](plan.md)。

## 1. 功能矩阵

每项记录实际命令、模式/表参数、源码 revision、镜像 hash、seed、预期、结果与失败诊断。单元与局部定向先执行，再扩展到真实 SoC；新入口在实施时定义，此处不列不存在的运行命令。

| ID / 阶段 | 检查内容 | 独立判断依据 |
| --- | --- | --- |
| G01 / S0 | OFF 与 M5 输入匹配、可重复运行 | 六程序镜像与比较清单一致；结果/提交序列一致，全程 cycles 差异必须解释 |
| G02 / S1 | 六类条件分支、JAL、非预测指令及非法编码 | 手工编码和期望立即数/目标，交叉对照主 IDU；覆盖正负偏移、x0/x15/x16、保留 funct3、JAL rd=x0 |
| G03 / S1 | XOR 索引、四种计数器状态、饱和、GHR/reset | 独立软件模型按事件推进；全 taken、全 not-taken、交替与相关分支、不同 PC 别名序列 |
| G04 / S1–S2 | 查询与训练同拍、同项/不同项、连续训练 | 查询看边沿前值，训练更新当前表项；预测时 index 保持，不能用提交时 GHR 重算，也不能回写过期 counter |
| G05 / S2 | IFQ/opbuf metadata 配对、反压与同拍替换 | 以指令 PC/实例顺序追踪实际预测；等待中改变其他表项/历史，已有上下文仍稳定，无重复查询接收/训练 |
| G06 / S2 | 条件分支方向四组合及 JAL/JALR | 实际指令结果与明确预期一致；预测正确不误清前端，错误恢复到正确 PC；JAL 写回 PC+4；JALR 保留原行为 |
| G07 / S2 | 普通预测与后端 redirect 分离 | 预测 taken 保留分支本身及 IFQ 中更老指令；新预测不触发全队列清空；目标为 PC+4 时分开统计方向和 NPC 错误 |
| G08 / S2–S3 | 旧请求、DROP、同拍响应/redirect、连续 redirect | 事务 scoreboard 无漏接/重复响应；旧响应及其错误不入队、不训练；最新恢复目标保留 |
| G09 / S2–S3 | 同步异常、IRQ、MRET、LSU 等待、共同 reset | DiffTest + 独立 EPC/cause/副作用预期；IRQ 优先丢弃的指令不训练，已接受访存先完成，trap/IRQ 不被预测匹配屏蔽 |
| G10 / S3 | 错误路径 store/CSR/非法指令及取指错误 | 错误路径不提交、不写内存/CSR、不触发架构异常、不训练；正常路径错误仍按 M5 合同触发 trap |
| G11 / S3 | 真实 SoC ISA、三种启动布局、UART、timer/RTT、随机等待 | 复用适用 M5 S1–S8 检查，保留 DiffTest、内存终态和协议断言；程序列表/seed 实际记录 |
| G12 / S3 | 检查器能抓到预测集成错误 | 测试专用注入至少覆盖错误预测 metadata 和漏恢复／错误训练；预期失败且诊断指向相应规则，不用普通超时代替所有定位 |
| G13 / S2–S4 | lint、filelist、综合 scope 与旧断言迁移 | 新模块包含于仿真/综合；原“预测恒不跳转”检查按模式调整；功能预测输入不再以观察豁免处理 |
| G14 / S4 | 三模式性能与 DC/PT 同条件对照 | 见下节；报告可由原始日志复算，未测试项单独记录 |
| G15 / S5 | 复现、QA、图与最终实现一致 | manifest/命令/结果入口齐全，既有报告不覆写，冻结交接包含 JOB-PREP-01 |

错误路径可产生已经被接受、必须排空的只读取指事务；G10 的“无副作用”主要检查执行端 store/CSR 与架构提交，不应把正常存在的推测取指误判为“完全没有总线流量”。定向目标使用当前有效代码存储区域，不依赖对设备 MMIO 的推测取指。

OFF/JAL_ONLY/GSHARE 均做基本功能 smoke；完整新增预测恢复矩阵在 GSHARE 下执行。S3 对最终默认候选执行既有适用系统回归，OFF 至少保留固定六程序及异常/IRQ 对照。具体集合由 S0 列明，不能以旧 runner 成功退出代替核对它实际运行的新二进制和模式。

## 2. 性能事件与计数

复用 [M5 比较合同](../5-ysyx-soc-integration/comparison-contract.md)和 [comparison-inputs.json](../5-ysyx-soc-integration/s8-validation/comparison-inputs.json)。三模式使用同一版观察逻辑，DiffTest 开启；固定无 IRQ 程序应有相同架构提交序列和最终内存，不能只比较退出码。

| 指标 | 定义 |
| --- | --- |
| cycles / commits / CPI | 沿用 M5 从仿真开始到结束的全程统计，含 reset/启动；CPI=cycles/commits |
| speedup | cycles_OFF / cycles_GSHARE；另报 cycles_JAL_ONLY / cycles_GSHARE 以归因条件分支预测 |
| 条件分支方向准确率 | 正常提交且实际方向等于保存预测方向的条件分支数 / 对应条件分支数；OFF/JAL_ONLY 的隐含方向为 not-taken |
| 预测覆盖 | 单独报告提交的合法条件分支总数、有有效预测 metadata 的数量；不能用减少分母隐藏漏预测 |
| NPC 错误 | 普通分支/JAL 的 actual_npc 与保存 pred_npc 不等；与方向错误分列 |
| redirect 分类 | 条件分支误预测、JAL、未预测 JALR、同步异常、IRQ、MRET；不以总 redirect 代替误预测数 |
| 前端开销 | 接受的取指请求数、redirect 时清除的 IFQ 项数、因恢复丢弃的响应数；包括 redirect 与响应同拍，不只数 DROP 状态 |
| 恢复等待 | 从一次恢复事件到第一条恢复后有效指令被送入 opbuf 的周期；期间再次恢复则标记被打断并重启，不能重复累加为净损失 |

恢复等待只是观测延迟，不自动等于可相加的 stall 损失。若新增 `main` 区间计数，应保留全程结果，并对三模式使用相同开始/结束事件重跑；训练是否包含启动阶段须注明。

PHT reset 初值固定为弱不跳转，所有程序冷启动。先报告每个固定程序，包括负收益；额外相关分支 micro-test 用于验证机制，与六程序结果分表，不选择事后最好看的测试替换原输入。RT-Thread/IRQ 和 UART 轮询的动态工作量随时间变化，仅作功能回归。

## 3. DC/PT 与归档

沿用 [M5 S7 cap90](../5-ysyx-soc-integration/s7-validation/baseline/README.md)：`ysyx_25030087` CPU 子系统、TT/0.9 V/25°C、同 DB、5 ns、ideal clock/ZeroWireload、相同 IO/reset 约束、DC Ultra/增量 DRC/max fanout 32/cap90。功耗不在验收范围，既有 reset 物理时序 deferred 和 leakage 零目标处置继续显式保留。

本阶段至少比较新实现 OFF 与 GSHARE；保留 M5 历史基线作为来源。优先同批运行两模式，记录 DC/PT 版本、输入快照、模式、参数、filelist、库/SDC 和脚本 hash。若沿用历史 OFF 数字，须证明其网表 scope/配置/约束与比较项一致，不能把其他改动的成本归因到预测器。

检查面积、setup/hold、capacitance/transition/fanout、coverage 和告警；新增表及 metadata 应为实际综合逻辑，观察计数器留在 simulation-only 路径。5 ns 的可比验收要求与 M5 一致，不能通过放宽 clock/IO/例外来掩盖新路径。PHT 初版是寄存器实现，报告含查询 mux、训练逻辑、目标加法及新增上下文存储的总成本。

服务器由用户手动同步和运行，助手负责准备可审查脚本输入及检查回传报告。缺工具结果时写“待验”；已有泄漏零目标单独处置，不要求为了表面 constraint clear 反复综合。

原始运行产物留在 `npc/build/`、`npc/flow/build/`；完成步骤时在本目录归档必要 manifest、结果表、日志摘要和精选报告，并链接完整产物位置。测试失败记录同样保留。S5 发布最终 `signoff.md`，列出通过／遗留范围，交接 [JOB-PREP-01](../../output/interview-readiness.md)。

## 4. 本轮执行状态

| ID | 状态与证据 |
| --- | --- |
| G01 | PASS；新 OFF 六镜像 cycles/commits/提交序列与 M5 一致，见 S0/S4 |
| G02–G04 | PASS；1858 predecode 检查、N=7/N=3 各 20000 模型事件、同拍与别名，见 S1 |
| G05–G08 | PASS；IFU 30000 拍独立 scoreboard、EXU 方向/NPC 矩阵、同拍与重复恢复；适用原协议测试，见 S2/S3 |
| G09–G10 | PASS；异常/IRQ/MRET、LSU 等待与 timer 回归，五类错误目标真实请求／丢弃证据及状态不变，见 S3 |
| G11 | PASS；M5 S3～S6 适用功能全组通过，146 次真实 SoC 正向运行；不另重复 S8 冻结发布流程 |
| G12 | PASS；错误 metadata 与漏恢复 mutant 均给出指定诊断 |
| G13 | PASS；22-source closure，三模式 × 四宏 profile，57 项 flow mock 检查 |
| G14 | 性能 PASS（18 次、完整提交 trace 一致且独立核对分支分母）；面积／时序待服务器 DC/PT |
| G15 | 本地文档、QA、闭环图与证据已归档；最终冻结／整体 sign-off 等 G14 的 PPA 审查，保留 JOB-PREP-01 |

以上是本轮具体覆盖范围，不宣称所有状态已穷尽或完整 ISA/物理签核。已知的指令地址对齐异常边界及早期 reset 时序边界见 S0/S4。
