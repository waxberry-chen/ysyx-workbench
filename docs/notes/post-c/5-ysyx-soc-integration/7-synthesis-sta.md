# M5 S7：CPU 子系统的综合与 STA

> 2026-10-29：S7 / M17 在约定范围内通过，采用 `soc-cpu-tt-5ns-s7-cap90`，见 [200 MHz 基线归档](s7-validation/baseline/README.md)。电气规则及 setup/hold 无违例，coverage/告警已逐类处置；用户接受仅记录 Ultra 自动 leakage 零目标，不重跑或改写原始结果。reset 物理时序仍暂缓。下一步 S8，见 §8。

S6 已验证接入 SoC 后的功能。S7 将这份 CPU 子系统 RTL 交给已有 DC/PT flow，回答在明确工艺库和接口预算下，需要多少标准单元面积、哪些路径限制时序，以及是否存在电气违例或漏检路径。本步复用 M4 的运行目录、快照、分类报告和失败检查，另建新范围的 filelist/config/SDC。

## 相关术语

| 术语 | 含义及本步对应 |
| --- | --- |
| Scope / top / filelist | scope 是本次评估的电路边界；top 是展开的顶层模块；filelist 是读取的源文件清单。文件出现在清单里并不代表其全部逻辑最终保留，只有 top 可达且影响输出/状态的逻辑才有必要映射。 |
| Elaboration（展开）/ mapping（映射） | 展开按参数、宏和实例建立电路层次；映射将逻辑实现为所选库的标准单元。Verilator 可以检查展开，实际 DC 映射须在服务器完成。 |
| SDC / budget | SDC 是时序约束脚本；budget 是分给设计或外部连接的时间预算。输入/输出 delay 是外部环境假设，不是测量本模块自身的延迟。 |
| Slew / load / fanout | slew 是边沿转换时间；load 是负载电容；fanout 在 DC 约束中是库中负载权重之和。三者指导不同方面的电气/驱动优化，不可相互等同。 |
| Case analysis / false path | case analysis 指定某信号在此工作模式下固定为 0/1；false path 排除指定起止关系的时序检查。前者用于禁用外部接口，后者仅用于当前暂缓的 reset 时序。 |
| Tie-off / observation port | tie-off 是固定连接到常量的端口；observation port 是用于观察执行状态的输出。真实 wrapper 的 slave 输出固定为 0，commit/monitor 输出未向外连接。 |
| WLM / pre-layout | WLM 是按统计负载估计互连的模型；pre-layout 表示尚无实际布局布线寄生。本步仍为普通综合与布局前分析。 |
| DRV / coverage | DRV 是电容、转换时间等设计规则违例；这里 coverage 指时序检查的 met/violated/untested 分类，不是功能测试覆盖率。 |
| Boundary optimization / ungrouping | 前者跨模块边界传播常量、未连接等信息并简化逻辑；后者合并模块层次。`compile_ultra -no_autoungroup` 保留默认边界优化，同时关闭自动层次合并。 |
| CCS / scalar capacitance | CCS 是 Composite Current Source 单元时序模型；接收电容可随 slew/load 变化。scalar capacitance 是库引脚的单个标量电容值；不同报告/检查接口不一定采用同一电容口径。 |
| Leakage / CDN | leakage power 是漏电功耗；优化目标与实际验收预算需分开。此次网表的 `CDN` 是触发器低有效异步清零引脚，属于复位网络负载。 |

## 1. 综合什么：沿用实际 CPU wrapper

```text
ysyx_25030087                     ← DC/PT top，61 个命名端口
└── subsystem: ysyx_soc_cpu
    ├── cpu: ysyx_core_axi4
    │   ├── core: ysyx_core       ← CPU、IFU/LSU AXI adapters
    │   └── AXI arbiter
    └── router: ysyx_axi4_router
        └── CLINT                ← mtime、mtimecmp、内部 timer IRQ

边界外：上游 SoC 互联、reset 延长链、UART/SPI/PSRAM 控制器、存储与仿真模型
```

采用 `SYNTHESIS NPC_FLASH_BOOT`：展开真实 [ysyx_25030087.sv](../../../../npc/vsrc/top/ysyx_25030087.sv)，复位 PC 为 `0x30000000`，IFQ 深度沿用 2，RV32E 的 16 个 GPR、无 M/C。不新建另一份硬件 wrapper；也不将 S6 延迟注入模块或 C++ harness 纳入面积。

20 个 `.sv` 按子模块到父模块的顺序列入 [soc_cpu.f](../../../../npc/flow/00_indata/filelists/soc_cpu.f)，primitive include 的 `ysyx_global.sv` 额外进入源快照。没有 SRAM macro、memory compiler 或新类型工艺库需求；寄存器堆及 CLINT 状态沿用当前 RTL，交给标准单元综合。继续使用 M4 核对过的标准单元 DB 和 DC/PT 安装即可。

### 观察信号怎样处理

真实 wrapper 已将 13 个 commit/monitor 输出留空；本次保持这些连接，允许 DC 优化掉纯观察逻辑，不增加输出端口去保留它们。仿真仍通过 monitor 观察内部 RTL，本步不修改功能源码。

M4 的 top 是 core + Lite adapters + arbiter，并保留观察输出；本次增加 router/CLINT/IRQ 等功能，同时改变观察边界。**新旧面积差不能直接解释为接口升级成本或优化收益。** 后续 GShare 应以本次最终通过的相同边界、库和 SDC 为比较起点。

## 2. 输入输出约束：先给每组端口确定用途

首轮沿用 TT / 5 ns（200 MHz）作为待验证目标；工艺角以服务器 `site.local.tcl` 和实际库报告为准。默认数值与 M4 比较假设一致，不是从完整 SoC 时序提取的预算。

| 端口组（按字段计） | 用途 | 本次约束 |
| --- | --- | --- |
| `clock`，1 个 | CPU 与 CLINT 的时钟 | `core_clk`，period=5 ns，ideal clock；setup/hold uncertainty=0.2/0.05 ns；slew=0.1 ns；source latency min/max=0 |
| `reset`，1 个 | 高有效共同复位输入，wrapper 反相为内部 `rst_n` | slew=0.1 ns，仅 `set_false_path -from reset`；无 input delay、无 case analysis |
| `io_master_{ar,aw,w}ready`，3 个 | SoC 接受请求的握手信号 | input min/max=0.2/2.0 ns，slew=0.1 ns |
| `io_master_rvalid/rdata/rresp/rid/rlast`，5 个 | SoC 返回读响应 | 同上，全部保留端口预算 |
| `io_master_bvalid/bresp/bid`，3 个 | SoC 返回写响应 | 同上 |
| `io_interrupt` + 18 个 slave 输入 | 当前外部 IRQ/ChipLink 关闭，没有访问源 | 明确列出并 `set_case_analysis 0`，不施加数据 delay；内部 timer IRQ 不在此集合 |
| 18 个 master 输出 | AR/AW/W 请求，以及 R/B READY | output min/max=0.2/2.0 ns，load=0.01 pF（10 fF） |
| 11 个 slave 输出 | 实际 wrapper 的常量 tie-off | 同样保留输出预算/load，预期没有活动数据路径 |

合计 32 个输入、29 个输出；向量字段在 DC/PT 中可能展开为多个 bit 对象。预算写在 [npc_soc_cpu.tcl](../../../../npc/flow/00_indata/configs/npc_soc_cpu.tcl)，施加对象写在 [soc_cpu.sdc](../../../../npc/flow/00_indata/constraints/soc_cpu.sdc)。

RID/BID/RLAST 的部分用途属于仿真协议检查，`SYNTHESIS` 下可能没有功能消费者；ID/LEN 等输出也有固定字段。这些无路径/常量对象需要按真实网表逐类解释，不要求为它们制造假路径，也不将活动 master 数据一并排除。

**5 ns 只改变本次综合/STA 目标。** 当前功能仿真和 AM `YSYXSOC_TIMER_HZ` 仍采用 100 MHz；本次没有改仿真时钟或软件时间单位。以后若真正把运行时钟改为 200 MHz，需要同步 timer/软件配置。

### Reset：已有数字机制，不代表物理时序已经闭合

S0 核对的上游 CPU reset 为外部 reset 与 10 级延迟链输出相或；仿真保持至少 20 周期并等待释放。这条延长链在当前综合 top **之外**，不能把仿真保持周期当成库引脚的恢复/移除或脉宽证明。

本次沿用用户已接受的早期 reset 处置：保留 RTL 异步复位及其电气负载，仅排除 reset 发起的时序路径。回传后重新核对 recovery/removal、脉宽和 untested 原因，不复制 M4 的数量。实际 reset 源、同步释放和物理到达模型确定后，重建 reset 约束并关闭此待办，参见 [reset TODO](../4-pre-soc-signoff/reset-timing-todo.md)。

### 电气规则与互连模型

首轮采用普通 `compile -map_effort medium`；第二轮切换 `compile_ultra -no_autoungroup`。第三轮采用逐库引脚最大电容 10% 裕量及增量 DRC 修复，电气规则通过；尝试关闭 Ultra 漏电优化未生效，见 §7.7。顶层 `max_fanout=32`、仅时钟网络关闭 DRC 修复的政策保持不变。DC 采用收紧后的最大电容，PT 按原库上限验收；min capacitance、max transition 保持原值。没有恢复强制端口 buffer 或设置全设计统一的 pF 上限。

DC/PT 使用同一 DB、工作条件和 WLM 策略：关闭按面积自动选模，mode 为 `top`，使用 site 指定模型或库默认模型。若仍为 ZeroWireload，应如实说明这是当前估计假设；不能宣称获得真实互连或物理 Fmax。

## 3. 哪些脚本改了，为什么 filelist 本身不够

| 层次/文件 | 本次修改 | 解决什么问题 |
| --- | --- | --- |
| `00_indata/filelists/soc_cpu.f` | 新建 20 文件源闭包 | 不混入旧 Lite top、仿真 RAM、SoC 外设模型 |
| `00_indata/configs/npc_soc_cpu.tcl`、`constraints/soc_cpu.sdc` | 新建 Flash 启动配置与真实端口预算 | 避免误用旧复位地址、`clk/rst_n` 名称或观察端口口径 |
| `flow/Makefile`、`01_common/flow.py` | 默认新配置；冻结 scope profile，按实际 top 查端口并验收导出网表 | 旧 driver 会拒绝新 top；旧 manifest 描述和网表校验也写死了 M4 top |
| `01_common/setup.tcl`、`02_syn/run.tcl`、`03_sta/run.tcl` | 时钟/reset 名称与 reset 不激活值来自快照中的 profile | 时钟 DRC 查询、PT 路径分组、可选功耗不能继续查 `clk/rst_n` |
| `01_common/capacitance.tcl` | LSU 诊断锚点改从 profile 读取 | 当前路径为 `subsystem/cpu/core/u_lsu`；否则旧脚本可能找不到负载却没有实际检查 |
| `04_tests/` | 将 flow 回归迁移到新 scope，补宏/网表 top/禁止错误 case analysis 的负例 | 本地检查脚本控制流和约束对象；不模拟真实综合面积/时序 |
| `npc/tests/synthesis_scope_check.py` | 检查新清单、Flash PC、4 种宏配置，逐项分类 lint | 保证综合配置去掉 DPI/SVA，仿真配置保留检查，未解释 warning 仍失败 |

旧 M4 配置文件保留，但原 RTL top 已退役，当前 preflight 会明确提示切回历史 revision 复现。M4 04/05 的网表和报告不改写。产物名称继续为 `outputs/core.v/core.ddc`，**文件中的 top 为 `ysyx_25030087`**；PT 消费同一次 run 的快照和网表。

## 4. 已完成的本地检查

```bash
make -C npc/flow check test scope-check
```

- SDC 对象合同通过：1 clock、11 个活动输入、29 个输出、19 个禁用输入；只有 reset false path，禁止用 case analysis 关闭 reset 或活动 master 输入。
- 初始 48 项 flow 测试通过，包括真实 Tcl 脚本在假 EDA 命令环境中的执行、产物错误/哈希变动拒绝、clock DRC 和 LSU 电容诊断；Ultra/功耗策略修改后为 51 项通过，电容裕量修改后为 54 项通过，回读精度修正后为 56 项通过，见 §7.4 / §7.6。mock 验证命令编排，不证明工具接受关闭 Ultra 漏电优化。
- 4 个预处理/lint 配置通过，均选择 Flash PC：综合、综合覆盖 DPI 宏、无 DPI 仿真、带 DPI 仿真。综合无 DPI/initial/assert/property 泄漏，无未处置宽度/latch/缺模块诊断。
- 综合两种配置各 41 条已审查 warning；仿真两种各 30 条：主要为真实 wrapper 未连接的观察输出、禁用 slave/IRQ 输入、指令立即数字段中不用的 opcode 位、综合去掉断言后的观察信号；仿真的 reset 同步/异步采样告警来自断言采样。完整逐项理由见 [本地证据](s7-validation/README.md)。

这些检查没有调用 DC/PT，不产生可用的面积/时序数据。未修改功能 RTL，因此本步不重复 S6 的长系统测试；S8 再对最终版本干净重建。

### 4.1 DC 前端兼容性：先声明信号，再引用（2026-10-30 补记）

用户在服务器综合时发现 [ysyx_core.sv](../../../../npc/vsrc/core/ysyx_core.sv) 的声明顺序会使 DC 报错，已通过 commit `9912da3af499daff1d2e168fef244f113f946e4b` 固化。原先 `assign redirect_target = interrupt_taken ? trap_target : exu_redirect_target;` 位于 `wire [31:0] trap_target;` 之前；该提交将两条 redirect 连续赋值一起移到 wire 声明区之后，表达式、位宽和连接关系不变。

这是一项 **DC 编译兼容性修复**，此前记录为“连续赋值位置差异”只描述了改动形式，没有解释必要性。本地 Verilator lint 没有拦住这个问题，不能用它通过来替代 DC 的 analyze/elaborate/link 验证。后续 RTL 统一采用“信号声明在前，引用它们的 assign、always 和实例化在后”的组织方式；新增跨模块接线时检查被引用信号的声明位置。

已核对 `9912da3`、当前本地文件与 cap90 的 `ysyx_core.sv` 快照三者 SHA-256 一致：`7a7c4ec68510f926497a53bb70ed63715a51357d3f816a56c40a888505b75252`。cap90 当时通过 dirty.patch 保存了该修复，后续才提交到 Git，因此 S7 基线已包含它，无需重综合。原 run 的 HEAD、dirty.patch、manifest 及 2026-10-29 审查统计仍按历史原样保留。

## 5. 服务器执行与回传

提交并同步本次 `npc/flow/`、`npc/tests/synthesis_scope_check.py` 和当前 `npc/vsrc/`。此综合范围不依赖服务器生成上游 SoC、Java/Mill、软件镜像或 NEMU。继续使用服务器已有且核对过的 `site.local.tcl`，保留 DB/工具路径；无需覆盖为 example。

在工程根目录执行：

```bash
make -C npc/flow preflight CONFIG=00_indata/configs/npc_soc_cpu.tcl SITE=00_indata/configs/site.local.tcl
make -C npc/flow all CONFIG=00_indata/configs/npc_soc_cpu.tcl SITE=00_indata/configs/site.local.tcl RUN_ID=soc-cpu-tt-5ns-s7
```

若希望分开查看 DC 和 PT：

```bash
make -C npc/flow synth CONFIG=00_indata/configs/npc_soc_cpu.tcl SITE=00_indata/configs/site.local.tcl RUN_ID=soc-cpu-tt-5ns-s7-split
make -C npc/flow sta RUN=build/soc-cpu-tt-5ns-s7-split
make -C npc/flow inspect RUN=build/soc-cpu-tt-5ns-s7-split
```

同一组中 `all` 和 `synth` 是两种运行方式，选择一种。新 run 不覆盖已有 ID；失败后保留诊断、换 ID，或确认不需保留后用已有 `clean` 目标清理指定 run。只有工具/库发生变化时才需要重做 probe 和库审查。

回传整个 `npc/flow/build/<RUN_ID>/`，包含 `manifest.json`、`inputs/`、`outputs/`、`logs/`、`reports/`。manifest 绑定服务器绝对路径，在本地拷贝上阅读报告即可；不要为了让 `inspect` 接受搬迁而修改 manifest。服务器原位置若要继续旧 run，而 flow 已更新，应使用该 run 快照中的 runner。

## 6. 回传后怎样判断 S7 是否完成

按以下顺序审查；2026-10-29 已完成，逐项结论见 [基线归档](s7-validation/baseline/README.md)：

1. **输入与结构**：top/宏/PC、库角和单位正确；core、CLINT 等实际映射，没有未解析引用、意外 latch、仿真模块或大段功能被常量化。
2. **约束完整性**：clock/reset、11 个活动输入与活动输出预算有效；`check_timing`、禁用弧和 coverage 的每类 untested 有依据，正常数据/CLINT IRQ 路径未被例外隐藏。
3. **面积与路径**：核对层次面积、全局 max/min 和四类边界路径；尤其观察新增 64 位计数/比较及中断控制是否形成新的最差路径。5 ns 不达标先保留诊断，不自动降频或加例外。
4. **电气与时序**：DC/PT `constraint_violations.rpt`、setup/hold、capacitance/slew、fanout、clock connectivity；需要同时解释工具检查差异和实际网络。
5. **记录结论**：归档选定报告、明确 reset/常量条件的影响；通过后建立 M5 新范围基线，作为 S8/GShare 的输入。

cap90 已完成审查及归档；leakage 目标按用户决定记录为已处置，保留自动判定，S7 / M17 在约定范围内通过。

## 7. 服务器迭代与当前问题（2026-10-29）

本节保留各轮迭代当时的发现和待办；最终处置以 §8 和基线归档为准。

两轮都基于 `ebf92abc976dab1f23787e6efb75de86356de45f`，源快照对照显示 RTL、SDC、DB 和工具相同，综合脚本只改变了 compile 命令；Ultra 改动保存在该 run 的 dirty patch / 输入快照中。均为 TT 0.9 V / 25°C、5 ns、ZeroWireload / top、ideal clock，输入与原始阶段产物的 manifest hash 核对通过。

| Run ID | 综合命令 | Cell area（库面积单位） | PT 最差 setup / hold slack（ns） | 未关闭问题 |
| --- | --- | ---: | --- | --- |
| `soc-cpu-tt-5ns-s7` | `compile -map_effort medium` | 11002.823905 | +1.220425 / +0.008754 | PT：7 条 min-capacitance |
| `soc-cpu-tt-5ns-s7-ultra` | `compile_ultra -no_autoungroup` | 9530.303856 | +2.444726 / +0.009693 | DC：1 条 max-leakage-power；PT：9 条 max-capacitance |

两轮 setup/hold 无违例；面积下降约 13.38% 是 Ultra 多种优化的共同结果，不全部归因于清理观察信号，也不代表本轮已建立合格基线。

### 7.1 首轮：跨层次无用逻辑留下零负载输出

7 个违例的实际电容均为 0，库下限为 0.000410 pF。以下路径省略 `subsystem/cpu/core/`：

| 引脚 | 实际信号及无负载原因 |
| --- | --- |
| `U6/Z`、`U7/Z` | 送入 CSR 的 `trap_epc[1:0]`；[CSR 对齐逻辑](../../../../npc/vsrc/core/ysyx_csr.sv)将 mepc 低两位固定为 0，上游 EPC 选择逻辑仍保留 |
| `U25/ZN`、`U26/Z` | `commit_redirect_reason[1:0]`，最终由 wrapper 留空 |
| `u_exu/U78/ZN`、`u_exu/U264/ZN`、`u_exu/U265/ZN` | `commit_mem_valid`、`commit_mem_error`、`commit_is_mmio`，最终由 wrapper 留空 |

M4 曾通过撤去 `set_fix_multiple_port_nets -all -buffer_constants` 消除 66 个无负载 buffer；该修复仍在，本次残留的是组合逻辑。切换 Ultra 后这 7 条违例消失。`U78` 等映射实例编号不跨 run 稳定，必须用同次报告对应同次 `outputs/core.v`。

### 7.2 Ultra：默认漏电优化与报告开关没有分开控制

Ultra 实验的 `syn.log` 明确记录 `Performing leakage power optimization. (PWR-850)`；DC 约束报告的漏电目标为 0、实际为 7377.631348 nW，约 7.38 μW。该 run 中 `power_enable=0` 只关闭后续功耗报告，没有另外关闭 Ultra 自动漏电优化；[driver](../../../../npc/flow/01_common/flow.py)又将所有违例行统一计入 `CONSTRAINT_FAIL`，没有区分优化目标与本阶段的验收预算。

重新读取同次 DDC 后，`max_leakage_power` 属性为 `UNAVAILABLE`，原漏电违例没有复现。因此不能把它解释为已保存的零功耗预算，也不能断言“没设置参数就必然失败”；需要在原综合会话核对策略与 compile 日志、最终约束报告。该值不是程序负载下的总功耗评估。

### 7.3 Ultra：复位网络的 DC/PT 电容检查口径差异

9 条违例均由 `INVD0BWP12T40P140` 驱动，分布在 arbiter、router、GPR 和 opbuf，主要负载为 `DFCNQD1BWP12T40P140/CDN`。现有 [电容诊断](../../../../npc/flow/01_common/capacitance.tcl)只查 LSU 请求寄存器 E pin，本次匹配数为 0；随后分别恢复 DDC / 网表，手动补查这 9 条网络，报告位于 Ultra run 的 `reports/debug/`。

九条网络的连接、驱动库上限、`report_net` min/max 电容逐条相同，线电容均为 0。以 `subsystem/cpu/arbiter/U6/ZN` 驱动 29 个 CDN 为例：

| 检查项 | DC | PT |
| --- | ---: | ---: |
| 驱动库上限（pF） | 0.049878 | 0.049878 |
| `report_net` 最大负载（pF） | 0.0535128 | 0.0535128 |
| `total_capacitance_max` 属性（pF） | 0.049573 | 0.053513 |
| 电容约束判定 | MET | VIOLATED |

库 CDN 标量 `capacitance≈0.001709 pF`，29 个之和约 0.04956 pF，与 DC 属性值吻合；报告中每个接收引脚的最大值为 0.00184527 pF，29 个之和约 0.0535128 pF，与 PT 违例值吻合。库属性打印舍入造成微小累加差异。其余八条也是标量电容之和低于上限、最大负载高于上限。

**证据支持 DC 约束结果与较小的标量口径一致，PT 与较大的接收电容口径一致。** 两边 `report_capacitance_use_ccs_receiver_model=true` 不保证优化/检查接口完全一致；不能仅凭 `report_net` 相同认定 DRC 检查相同。参考 PT User Guide §9-7。此次重读 DC 后 WLM 选模方式恢复为自动，但仍选 ZeroWireload、线电容仍为零，不能解释该差值；重放还需显式恢复会话设置。

### 7.4 正式接入 Ultra 与功耗策略（本地已实施，服务器待验证）

本节保留当时的实现方案；后续 cap90 服务器日志证实 `set_leakage_optimization false` 不能关闭该版本 Ultra 的漏电优化，以下“关闭”只代表当时意图，实际结果与修订方向见 §7.7。

本阶段的优化与验收重点是面积、时序和电气规则，尚无程序活动驱动的功耗目标。因此采用以下明确策略：

```tcl
set_leakage_optimization false
set_dynamic_optimization false
require_true [compile_ultra -no_autoungroup] "compile_ultra failed"
```

`-no_autoungroup` 关闭自动打平用户层次，便于按模块阅读报告；保留 Ultra 默认边界优化，让未连接/常量信息跨模块传播。该选项不等于禁止所有内部结构变化，例如 DesignWare 的展开另有规则。仍使用 wire-load 模式，没有引入物理综合。Ultra 命令失败直接结束，不回退普通 compile。

功耗分为三个独立决策：**优化关闭；报告可选；预算未制定。** `power_enable=1` 只在网表导出后尝试粗估报告，不启用功耗优化；没有添加零功耗或任意大数预算。关闭优化不表示电路不消耗功耗。`report_constraint` 中如果仍有功耗违例，driver 继续报告失败，保留原文供核查。

| 改动位置 | 实现与阅读重点 |
| --- | --- |
| [02_syn/run.tcl](../../../../npc/flow/02_syn/run.tcl)，阶段 4 / 7 | 综合前显式设置两个优化开关并调用 Ultra；记录 `NPC_SYN_POWER_POLICY` 和 `NPC_SYN_COMPILE`；可选报告保持在导出之后 |
| [npc_soc_cpu.tcl](../../../../npc/flow/00_indata/configs/npc_soc_cpu.tcl)、[flow README](../../../../npc/flow/README.md) | 说明 `power_enable` 仅为报告开关，以及 license、模式、预算边界 |
| [eda_mock.tcl](../../../../npc/flow/04_tests/eda_mock.tcl)、[test_flow.py](../../../../npc/flow/04_tests/test_flow.py) | 检查 Ultra 参数和优化开关执行顺序；报告开/关都不启用优化；策略命令错误或 Ultra 返回失败时不导出网表 |

接入 Ultra/功耗策略时执行 `make -C npc/flow check test`：配置/SDC 检查通过，51 项测试通过。未修改电容查询脚本、SDC 或功能 RTL。mock 只证明控制流；新策略的 DC V-2023.12-SP5 兼容性、漏电目标是否消失、映射变化与 PT 结果仍待服务器运行。日志中的 `requested` 表示请求的策略，不冒充工具内部状态回读。

手册依据：DC P-2019.03 §7-19–7-20、§8-23 说明默认漏电优化及功耗优化控制；§10-2–10-3、§12-1–12-2 说明 Ultra 与边界优化。检索入口见 [manual-index](../4-pre-soc-signoff/manual-index.md)。

### 7.5 电容优化口径的控制项调查（尚未确认）

调查问题：**DC V-2023.12-SP5 在当前 wire-load 模式下，是否提供受支持的设置，使 `compile_ultra` 的最大电容 DRC 优化使用与 PT 一致的接收电容口径？**

要分别确认延迟计算、报告显示和综合 DRC 优化三者的控制。两边 `report_capacitance_use_ccs_receiver_model` 已为 true，仅重设这一报告变量不足以解释或解决现象。也不能把 `compile_enable_dyn_max_cap` 当作接收电容开关：DC §8-8–8-9 描述的是按频率确定驱动端允许的电容上限，改变的是 required 一侧。

本地 DC P-2019.03 §4-4（PDF 114）说明综合/布线前优化可能只使用部分 CCS 数据；PT L-2016.06 §9-7 说明 CCS 接收电容参与报告/约束检查，并提示工具间可能存在差异。另核对了 [Synopsys DC V-2023.12 User Guide 的公开转存](https://studylib.net/doc/27956669/design-compiler%C2%AE-user-guide-version-v-2023.12--december-2023)：第 110 页仍保留部分 CCS 数据可能不参与优化的说明，第 218–220 页介绍最大电容 DRC，但未在这些小节给出统一接收电容优化口径的控制项。

**尚不能据 User Guide 断言 V-2023.12-SP5 有或没有该设置。** 当前需要服务器随版本的命令/变量手册或 Synopsys 支持确认。首先核对 `man report_capacitance_use_ccs_receiver_model`、`man rc_receiver_model_mode` 的作用范围；后者是延迟计算候选，不能直接视为 DRC 修复开关。

若找到候选，应核对它是否改变 DC 实际 DRC 计算与驱动/负载选择，再由 PT 验证。后续讨论决定先尝试 §7.6 的 10% 综合裕量，不把找到统一口径的开关作为本轮试验前提；该决定不等于已经证明工具没有相应设置。

这九条网络的查询保留为本次 debug 证据，**不扩展为长期通用 flow 查询入口**；现有 LSU 诊断保持原样。由用户同步脚本、新建 run 重跑，最终仍须完成 coverage/告警审查。

原始约束报告和两份 debug 报告见 [S7 证据索引](s7-validation/README.md#服务器结果与诊断入口)。当前报告留在回传的 build 目录，尚未作长期归档；S7 / M17 仍未通过。

### 7.6 尝试 10% 最大电容裕量与增量 DRC 修复

**数值依据。** 九条网络的 PT 实际电容比 DC 属性值大约 6.5%～7.95%。以最大比值 1.0795 估计，DC 目标需要小于原库上限除以 1.0795；对 0.049878 pF 的驱动，上限约为 0.04621 pF。本轮选择原上限的 90%，约 0.0448902 pF，作为可验证的试验起点。该比例来自当前库、模式和网络，不是跨工艺/跨设计通用常数；重映射改变负载组合后仍以 PT 结果为准。

**作用范围。** 在 DC 中读取本次 `site.library_name` 对应的库输出/inout 引脚，对已有 `max_capacitance` 的对象执行 `新上限 = 原上限 × 0.90`。使用库引脚属性使后续映射选用的实例也继承该限制，避免依赖不稳定的 `U6/U7` 实例名。它会作用于使用这些单元的其他网络，所以仍需评估面积和时序代价。未指定上限的对象记录为 `UNCHANGED`，不人为补值。

这里通过 `set_attribute` 修改的是 **DC 会话内的最大电容限制**，不修改接收引脚标量电容、CCS 表、最小电容或磁盘 `.db`。没有调用 `write_lib`。PT 是独立进程，读取原始 DB/原始 SDC，仍采用原始库上限。相应地，新 DC 约束报告中的 required 可能比 PT 小 10%，这是显式裕量策略；不会改变两工具计算 actual 的方法。导出的 `dc.sdc` 不能代替这项库属性策略，重读 DDC 时也需重新施加。

**源码与执行顺序。**

| 文件 | 本轮修改与用途 |
| --- | --- |
| [02_syn/run.tcl](../../../../npc/flow/02_syn/run.tcl)，阶段 1 | 参数 `syn_max_capacitance_scale=0.90`；读取 DB、保存原始库报告，然后施加裕量，先于首次 compile |
| [02_syn/max_capacitance_margin.tcl](../../../../npc/flow/02_syn/max_capacitance_margin.tcl) | 枚举目标库引脚、读取原值、设置比例上限并回读；记录无上限对象；无有效对象、写入失败或回读不符时停止 |
| [02_syn/run.tcl](../../../../npc/flow/02_syn/run.tcl)，阶段 4 | 完整 Ultra 后执行 `compile_ultra -incremental -only_design_rule`；两个 pass 后核对 margin、fanout 与 clock DRC 策略，再导出网表 |
| [01_common/flow.py](../../../../npc/flow/01_common/flow.py) | 将 `reports/syn/environment/max_capacitance_margin.rpt` 列为必需报告，并纳入原有报告错误检查与产物 hash |
| [04_tests](../../../../npc/flow/04_tests/test_flow.py) | 验证不同上限各乘 0.90、未施加对象可见、DB 不写回、PT 原值、属性设置/保留失败及增量修复失败时停止导出 |

手册依据：DC P-2019.03 §6-18–6-19 介绍属性设置/查询，§8-4 允许施加更严格的 DRC；§8-25 规定 Ultra 的 `-only_design_rule` 必须配合 `-incremental`。[V-2023.12 手册](https://studylib.net/doc/27956669/design-compiler%C2%AE-user-guide-version-v-2023.12--december-2023)第 165–166 页和第 235 页提供对应说明。当前已知的是这些命令机制；**V-2023.12-SP5 对本库 `lib_pin.max_capacitance` 的写入及优化效果尚待真实运行确认**。脚本回读失败会中止，不静默回退到全设计统一上限。

**本地结果与服务器阅读入口。** `make -C npc/flow check test` 通过，54 项测试通过；未改功能 RTL/SDC，未重跑 S6。新增报告包含 `lib_pin / original_max / synthesis_max / readback` 和施加/跳过数量；`library_*.rpt` 仍为收紧前的原库信息。属性回读只证明设置保留，不等于优化器已经按该值完成修复。

用户同步后可用新的 RUN_ID：

```bash
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=soc-cpu-tt-5ns-s7-cap90
```

回传后依次检查：DC 裕量报告及两个 compile pass 日志；DC 实际 required/违例；PT 原库电容违例是否清零；再审查 min capacitance、slew、setup/hold、coverage、clock connectivity 和面积变化。原始九条复位网络实例可能因重映射改名，按新 run 的网表和报告解释。当前未宣称电容问题已经消除，M17 仍待验收。

**服务器回读舍入修正（2026-10-29）。** 首次施加裕量时，`OAI32D0BWP12T40P140/ZN` 报 `expected=0.0194895 actual=0.019490`。两者相差 `5×10⁻⁷ pF`，符合六位小数的舍入，但超过原校验的纯相对容差 `expected×10⁻⁵ ≈ 1.95×10⁻⁷ pF`，因此被脚本误判为设置失败。现将即时回读和两次 compile 后的检查统一为 `abs(actual−expected) ≤ max(5×10⁻⁷, abs(expected)×10⁻⁵) + 10⁻¹²`，容纳半个小数末位的舍入及极小浮点误差。只修改校验容差，仍施加原库上限的 90%，PT 仍使用原库上限。

本地 `make -C npc/flow check test` 再次通过，共 56 项；新增测试复现上述六位小数回读，并确认更大偏差、未施加/重复施加裕量和非数值回读仍被拒绝。服务器同步修正后用新 RUN_ID（例如 `soc-cpu-tt-5ns-s7-cap90-r2`）重跑；这次修正不代表真实电容违例已关闭。

### 7.7 cap90 回传：电气规则通过，Ultra 漏电优化无法关闭

**输入与结果。** `soc-cpu-tt-5ns-s7-cap90` 的 Git HEAD 为 `11a2608c224f05ed46c2bee57805a5300aa35135`。与前一轮 Ultra 对照，冻结 RTL、SDC、配置值及 manifest 中的 DB/工具 hash 相同；本地重新计算的 94 个冻结输入/阶段产物 hash 均匹配。外部服务器工具未在本地执行。综合脚本快照与当前源码一致，包含 10% 电容裕量、回读容差修正、两次 Ultra pass 和尝试关闭功耗优化的命令。

| 项目 | 前轮 Ultra | cap90 |
| --- | ---: | ---: |
| Cell area（library_area） | 9530.303856 | 9530.135856 |
| PT 最差 setup / hold slack（ns） | +2.444726 / +0.009693 | +2.444726 / +0.009693 |
| PT 约束违例行数 | 9（max capacitance） | 0 |
| DC 约束违例 | 1（max leakage power） | 1（max leakage power） |
| DC leakage 实际值（nW） | 7377.631348 | 7389.414551 |

裕量报告记录 1321 个库引脚收紧为原上限的 90%，两次 compile 后回读均通过；PT 独立读取原始库，约束报告无违例。这说明本轮组合策略已消除先前电容违例；面积变化为 −0.168 library_area（约 −0.0018%），最差 setup/hold 不变。没有单独关闭增量 pass 的对照，不能将改善全部归因于其中一个 pass，也不据此宣称 DC/PT 电容算法已统一。

**漏电问题已定位。** `logs/syn.log:661` 的 PWR-884 明确写道：

```text
compile_ultra automatically performs leakage power optimization.
It no longer needs to be enabled, and it cannot be disabled within compile_ultra.
```

前面确实执行了 `set_leakage_optimization false`，随后仍有 PWR-850。这不是同步遗漏或开关未送达，而是该版本 Ultra 的行为；先前从可用命令推断能够关闭 Ultra 漏电优化不成立。原始 DC 报告为 required=0、actual=7389.414551 nW（约 7.389 μW）。本工程未制定功耗预算，也未启用可选功耗报告，零目标不能解释为项目要求零漏电或真实芯片功耗超标。

**下一步建议（尚未修改脚本和验收判定）。** 保留 Ultra 的自动漏电优化，删除不能生效的关闭意图与日志描述；动态功耗优化和可选报告继续分别控制。完整保留 `report_constraint -all_violators`，在结果解释中将无项目预算的 leakage 优化目标与 timing/electrical 验收分开；不能统一忽略所有功耗违例，未来若制定真实功耗预算必须纳入检查。当前 driver 仍按所有 `VIOLATED` 行判为 `CONSTRAINT_FAIL`，因此本轮保持 DC `CONSTRAINT_FAIL`、PT `REVIEW_REQUIRED`，没有修改回传 manifest 或宣告 S7 通过。

**Coverage 初审。** setup/hold 各 1623 项全部 met；9120 项 untested 与前一轮相同：2986 项 recovery/removal 为异步 CDN/SDN 的 `no_startpoint_clock`，5972 项 reset/set 脉宽为 `no_clock`，对应当前明确暂缓的 reset 物理时序；162 项输出检查为 81 个常量输出各自的 setup/hold `no_paths`。`report_disable_timing` 的 81 项均为传播常量 `p`，没有 loop-breaking 标记；`check_timing -verbose` 成功。高扇出报告唯一网络仍为 ideal `clock`。这些记录支持后续基线审查，不替代实际 reset 设计及完整告警处置。

原始报告入口见 [S7 证据索引](s7-validation/README.md#服务器结果与诊断入口)。本次仅审查回传产物并更新记录，没有重跑 EDA 或功能回归。

## 8. 最终验收与 S8 交接（2026-10-29）

用户决定 leakage 问题在文档说明即可，不为清空约束报告而 re-synth。按此范围完成结构、时钟连接、关键路径、coverage 和告警审查，采用现有 cap90 建立 **S7 / M17 基线**，没有修改 flow 脚本、回传 manifest 或 RTL。

- 面积 **9530.135856 library_area**；PT 最差 setup/hold **+2.444726 / +0.009693 ns**，电气违例 0。
- 1623 个触发器 CP 与高扇出 `clock` 的直接连接集合完全匹配；最终 1228 条 unloaded 告警均指层次输出，无叶级输出落入该集合。
- 9120 项 untested 已分解为 **8958 项 reset 物理时序 deferred + 162 项常量输出检查**；没有其他未解释类别或 loop-breaking 禁用弧。
- 45 个输入、49 个阶段产物 hash 核对通过；72 份原始报告/日志/追溯文件按字节复制，另保存审查统计及文件 hash。

详细阅读：[基线总结、路径导读与告警表](s7-validation/baseline/README.md)、[派生统计](s7-validation/baseline/review.json)、[归档清单](s7-validation/baseline/archive.json)。原始 DC `CONSTRAINT_FAIL`、PT `REVIEW_REQUIRED` 保持不变，人工验收的条件和 leakage 处置依据独立记录。

本步无未处置阻塞。S8 接手冻结版本的干净功能构建与总验收，纳入已由 `9912da3` 固化的 DC 声明顺序修复（与服务器 snapshot 一致，见 §4.1），汇总各阶段输入/证据，固定后续 GShare 的程序、存储、统计口径和相同 PPA 约束；不把本次报告审查计作 S8 干净复现。
