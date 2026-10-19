# S6：最终回归、基线复现与交接

2026-10-19：**本地最终回归与服务器独立复现均通过，S6 完成。** [05 新 run](synthesis-results/05-s6-reproduction/README.md)复现 [04 基线](synthesis-results/04-200mhz-baseline/README.md)，本轮 [M4 总验收](signoff.md)关闭，无当前范围内阻塞。下文保留复现条件与操作入口。

## 1. 固定输入与版本关系

| 项目 | 固定内容 / 本次核对 |
| --- | --- |
| S3 测量源 | `9e449fac5b8abe863c6bd5c90f79a1c4230607a1`；服务器只有 Makefile 默认 SITE 的已记录 dirty 修改 |
| S6 本地回归源 | `415c87b`，完整 HEAD 见[本地验证 manifest](s6-validation/manifest.json)；启动回归前工作区干净 |
| 两版本差异 | `dd5dfdf`、`415c87b` 仅提交文档/证据，无 RTL、仿真、软件或 flow 执行代码变更 |
| 当前与 04 快照 | 32 份 `inputs/npc/` 文件中 31 份逐字节一致，包括全部 17 份 RTL；唯一差异是 `npc/flow/Makefile` 的默认 SITE |
| 消除 SITE 差异的方法 | 新运行显式传 `SITE=00_indata/configs/site.local.tcl`，不需要把服务器的 Makefile 定制补丁带回源码 |
| source closure | 16 个有序 SV 源 + `ysyx_global.sv` include；`SYNTHESIS`；无参数覆盖 |
| DUT / ISA | `ysyx_core_axi4lite`；Core + IFU/LSU adapters + Arbiter；16 GPR、无 M/C、四 CSR 的限定契约 |
| 参数与输出策略 | PC_RST=0x80000000，IFQ_DEPTH=2，保留 commit/monitor 输出 |
| 时序与环境 | TT / 0.9 V / 25°C / RVT；5 ns；ideal clock；ZeroWireload；ns/pF；area 为 library_area |
| 综合策略 | 普通 `compile -map_effort medium`；DC 顶层 max_fanout=32；关闭 clock network DRC 修复；无全局强制 multi-port buffer |
| reset / 功耗 | 仅 rst_n false path，脉宽和释放时序 deferred；power_enable=0，功耗未评估 |

数据 I/O min/max=0.2/2 ns，输入/clock slew=0.1 ns，output load=0.01 pF，setup/hold uncertainty=0.2/0.05 ns，source latency=0；均为既有早期接口条件。精确定义以 [04 的冻结配置](synthesis-results/04-200mhz-baseline/provenance/design-config.tcl)和 [SDC](synthesis-results/04-200mhz-baseline/provenance/core.sdc)为准。

本次完整核验本地回传 run 的 **37 项输入、23 项 DC 产物、25 项 PT 产物**及 **51 份长期归档**的 hash；归档 manifest 与原 run 一致。核对记录见 [input-audit.json](s6-validation/input-audit.json)。没有改写旧 run、原始报告或原工具 `REVIEW_REQUIRED` 状态。

上述本地准备阶段不具备原 manifest 中的 DC/PT、DB 和 DC 安装 setup 文件，因此这里只是已回传 04 文件的完整性与源版本核验，不是新的 EDA 运行。随后服务器独立执行了 05；其阶段内外部依赖检查和复现对照见第 6 节，不将离线报告解析冒充完整 `inspect`。

## 2. 本地最终回归：本次重新执行的证据

工具为 Verilator 5.008、RISC-V GCC 11.4.0；Python/Tcl 版本与命令退出码见[验证 manifest](s6-validation/manifest.json)。使用既有增量构建目录，重新执行测试与程序，没有声称所有二进制均从空目录重编译。`git_commit=` 禁用课程构建自动 Git 记录，不改变 DUT 功能。

| 检查 | 2026-10-19 结果 | 长期证据 |
| --- | --- | --- |
| flow check/test | 44/44 测试通过；1 clock、8 data inputs、24 outputs，仅 rst_n 例外 | [flow 日志](s6-validation/logs/flow-check-test.log) |
| ISA/异常契约 | IDU 360192 独立 checks；GPR/CSR 两种宏、EXU 定向通过；legacy/B1 非法程序各 97 个预期 trap，合法程序均零异常 | [日志](s6-validation/logs/isa-contract.log)、[程序结果](s6-validation/results/isa-contract.json) |
| 综合宏/源闭包 | 四个 profile 均通过；宏隔离、无非预期 lint 项 | [日志](s6-validation/logs/scope.log)、[manifest](s6-validation/results/scope-manifest.json) |
| B1 最终功能验收 | 三个 top lint、定向/随机 fabric、53 项固定系统、23 项 closure、C01–C13 必测 coverage 通过 | [日志](s6-validation/logs/b1-signoff.log)、[53 项](s6-validation/results/b1-system.csv)、[23 项](s6-validation/results/b1-closure.csv)、[coverage](s6-validation/results/coverage-summary.csv) |
| legacy 影响检查 | 定向测试、34/34 CPU tests、固定 trace 通过 | [日志](s6-validation/logs/legacy.log) |
| legacy 延迟回归 | add seeds 1–10 通过 | [日志](s6-validation/logs/legacy-seeds.log) |

legacy trace hash 为 `d18898e78483a270397c27594904e2fd520d84b7dc7c7dbac9401790f6d34392`，与 S2.5 一致。B1 两个 RT-Thread 场景各 262561 commits；其余数量与 [S2.5](2.5-isa-contract.md)对应，没有扩大 ISA 合规声明。

`flow test` 日志内的模拟 `TIMING_FAIL` 等是负向用例输出，以 unittest 的 44 项全部通过及退出码 0 判断测试成功；它们不是本次 DC/PT 实测结果。

复现本地验证的命令，从仓库根目录执行：

```bash
export NPC_HOME="$PWD/npc"
export NEMU_HOME="$PWD/nemu"
export AM_HOME="$PWD/abstract-machine"
make -C npc/flow check test
make -C npc isa-contract-test git_commit=
make -C npc synthesis-scope-check git_commit=
make -C npc b1-signoff git_commit=
make -C npc axi4lite-directed-regress axi4lite-cpu-regress axi4lite-trace-test git_commit=
make -C npc seed-regress IMG=../am-kernels/tests/cpu-tests/build/add-riscv32e-npc.bin git_commit=
```

需要既有 NEMU shared-library 配置（32 槽 GPR ABI）、Verilator、交叉编译器及各子工程依赖。当前环境已具备，本次没有改变 NEMU 配置或安装工具。功能回归覆盖完整 B1 的部分系统行为，但面积/时序测量 scope 仍仅为 core + adapters + Arbiter。

## 3. 服务器独立复现：已完成及后续操作入口

### 3.1 运行前

由用户手动同步并执行。采用包含上述功能/flow 版本的已提交源码；本轮后续改动只涉及交接文档与 flow README。保持工作区的实现输入干净，不要为复现改动 RTL、SDC、周期、端口预算或 fanout 策略。

继续使用已核对的私有 `site.local.tcl`，不要用 example 覆盖它：

- DC V-2023.12-SP5、PT T-2022.03-SP5；license 环境在服务器准备。
- 库 `tcbn28hpcplusbwp12t40p140tt0p9v25c_ccs`，operating condition=`tt0p9v25c`；库路径及 hash 与 04 对照。
- DC 安装 `.synopsys_dc.setup`、加载库与其他启动环境保持原条件；PT 使用 `-no_init`。
- `library_reviewed=1`；ns/pF、area_unit=`library_area`、wire_load_model=`library_default`；实际报告应仍为 ZeroWireload。
- 显式指定 SITE；若服务器仍有 Makefile 默认值的本地修改，先保存所需定制并使用干净源码，不将无关变更混入本轮输入。

原 site 和外部文件 hash 的依据在 [04 manifest](synthesis-results/04-200mhz-baseline/provenance/manifest.json)。`preflight` 只验证路径和配置；不能代替实际启动、license 和 EDA 执行。工具/库未变化时不要求为形式重跑 probe；变化则先 probe，并说明该次不是完全相同环境的复现。

### 3.2 命令

从服务器仓库根目录执行，选择尚不存在的 RUN_ID。**不要清理或复用 04 的目录。** 如果下面的 ID 已存在，另选新 ID 并在后续 `RUN` 中使用相同名字。

```bash
git rev-parse HEAD
git status --short
make -C npc/flow preflight SITE=00_indata/configs/site.local.tcl
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-5ns-s6-repro
make -C npc/flow inspect RUN=build/core-tt-5ns-s6-repro
```

`all` 从不存在的目录创建新的输入快照，先 DC、再 PT，不复用 04 网表。`inspect` 在服务器核验外部/内部文件 hash 和阶段报告；成功时仍可能显示 `REVIEW_REQUIRED`，这是预期的人工审查入口，不应修改工具状态来伪造 PASS。

本次执行不需要更改 clock、reset、load 或频率。若需要探究这些参数，另开优化实验，不与 S6 复现混在同一个 run。

### 3.3 回传与留存

回传 `npc/flow/build/core-tt-5ns-s6-repro/` 的完整结果，包括 `inputs/`、`logs/`、`reports/`、`outputs/` 和 `manifest.json`。网表/DDC 可以作为本地/服务器运行产物保存，不提交 Git；长期归档只选有用的报告和追溯信息。工艺 DB 不随结果回传或提交。

不要改写 manifest 中的原路径或 hash。回传副本供离线审阅，完整 `inspect` 仍在具有原路径和外部依赖的服务器执行。保留 04 原目录及其归档。

## 4. 收到结果后怎样判定复现成功

| 对照项 | 04 参考 / 新 run 要求 |
| --- | --- |
| 输入闭包 | RTL、filelist、宏/参数、设计配置、SDC、DC/PT 执行代码一致；site 求值与工具/库条件一致 |
| 允许的追溯差异 | RUN_ID/路径、时间、文档提交 HEAD、已解释的 Makefile 默认 SITE；不能据此要求所有快照 hash 完全相同 |
| 完整性与执行 | 输入和产物 hash 自洽；DC/PT COMPLETE，报告齐全；无解析错误或未映射逻辑 |
| 电气/数据时序 | DC/PT constraint violations=0；max/min WNS/TNS/违例端点数=0 |
| 面积与单元 | area 9242.855942 library_area，6909 leaf cells，其中 1509 sequential |
| setup/hold | 全局 +0.596843 / +0.008754 ns；Reg2Reg max +1.678541 ns；路径类型和关键逻辑一致 |
| 负载与 clock | LSU E pin 分支 25/25/18，最大分支 0.0405621 pF；clk 直接驱动 1509 CP，无普通 fanout 32 修复产生的 clock tree |
| coverage | 20180 total、10730 met、0 violated、9450 untested；9426 reset deferred + 24 mtvec 常量条件禁用逐类对应 |
| warning/禁用弧 | 按 [04 审查](synthesis-results/04-200mhz-baseline/README.md#5-结构与其他告警审查)逐类对照；新增类型或对象需解释，不自动沿用总数豁免 |

在相同工具/库/输入下，优先要求数值在报告精度内一致。输出文本含日期、路径等字段，DDC 也不承诺逐字节确定性，因此不以全部输出 hash 与旧 run 相同作为必要条件；各自 hash 自洽仍是必须的。

若面积、时序、映射或 coverage 有超过显示舍入的变化，先比较源/参数/库/启动环境与工具设置，再解释变化。**“两次都没有 violation”不足以独立证明相同基线可复现**，也不预先规定一个任意百分比将差异自动接受。

## 5. 已知限制与关闭条件

已审查、不阻塞本轮范围的事项：

- reset 的 recovery/removal、有效脉宽和真实分发网络 deferred，恢复条件见 [reset TODO](reset-timing-todo.md)。
- 24 个常量条件禁用项有 RTL/网表依据；不是功能路径漏时钟。
- TIM-134/135、结构连接告警、PTE-003、UITE-502 等依据沿用 04 的具体对象审查；UITE-416 的两个端点对应仍是交叉证据推断，不升级为工具逐名证明。
- 只接受单 TT、ideal clock、ZeroWireload 下的面积/数据时序；area 未确认 μm²；功耗、GLS/FM、四值、CTS/PnR 和全 PVT 未评估。

**服务器复现阻塞已关闭。** 05 满足第 4 节对照要求；I12 与 S6 通过，已填写 [M4 signoff](signoff.md)，后续进入 M5。上述 reset/物理/功耗等范围限制继续保留。

## 6. 2026-10-19 回传结果与实际偏差

新 run `core-tt-5ns-s6-repro` 在北京时间 19:13 创建，DC/PT 均 COMPLETE、exit 0。面积 9242.855942 library_area，setup/hold +0.596843/+0.008754 ns；coverage、负载和告警与 04 一致。37 输入、23 DC/25 PT 产物 hash 核对通过；43 份报告除日期和 QoR 的四行耗时外相同；core.v 和 dc.sdc 仅生成日期不同。详见 [05 原始归档与机器可读对照](synthesis-results/05-s6-reproduction/README.md)。

服务器仍使用 `9e449fac`，而不是本地文档 HEAD `415c87b`，且保留同一份 Makefile 默认 SITE 修改。这是已解释的交接偏差：实际设计配置、执行源码及 17 份 RTL 相同，两次 37 输入只有新 run 路径不同；因此接受其为同一实现的独立复现，不声称 Git 工作区完全干净。

外部 hash 在服务器成功阶段的前后由原 driver 校验，本地只核对记录一致性和回传文件；未收到单独 `inspect` 终端记录，不声称本地运行过完整外部检查。工具 REVIEW_REQUIRED 保留，人工验收独立记录。S6 本地验证 manifest 的 `S6_PENDING_SERVER_REPRODUCTION` 是回传前的历史状态，原样保留；本节、05 和最终 signoff 给出完成后的结论。
