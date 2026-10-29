# M5 S7：CPU 子系统的综合与 STA 准备

> 2026-10-29：本地准备与检查完成，真实服务器 DC/PT 待运行回传。M17 尚未验收，不提前填写面积、时序或 coverage 通过结论。

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

普通 `compile -map_effort medium`、顶层 `max_fanout=32`、仅时钟网络关闭 DRC 修复的政策保持不变。库的 max/min capacitance、max transition 继续生效；不恢复强制端口 buffer，也不加人为更严的全局电容目标。

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
- 48 项 flow 测试通过，包括真实 Tcl 脚本在假 EDA 命令环境中的执行、产物错误/哈希变动拒绝、clock DRC 和 LSU 电容诊断。
- 4 个预处理/lint 配置通过，均选择 Flash PC：综合、综合覆盖 DPI 宏、无 DPI 仿真、带 DPI 仿真。综合无 DPI/initial/assert/property 泄漏，无未处置宽度/latch/缺模块诊断。
- 综合两种配置各 41 条已审查 warning；仿真两种各 30 条：主要为真实 wrapper 未连接的观察输出、禁用 slave/IRQ 输入、指令立即数字段中不用的 opcode 位、综合去掉断言后的观察信号；仿真的 reset 同步/异步采样告警来自断言采样。完整逐项理由见 [本地证据](s7-validation/README.md)。

这些检查没有调用 DC/PT，不产生可用的面积/时序数据。未修改功能 RTL，因此本步不重复 S6 的长系统测试；S8 再对最终版本干净重建。

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

按以下顺序审查，M17 仍为待验：

1. **输入与结构**：top/宏/PC、库角和单位正确；core、CLINT 等实际映射，没有未解析引用、意外 latch、仿真模块或大段功能被常量化。
2. **约束完整性**：clock/reset、11 个活动输入与活动输出预算有效；`check_timing`、禁用弧和 coverage 的每类 untested 有依据，正常数据/CLINT IRQ 路径未被例外隐藏。
3. **面积与路径**：核对层次面积、全局 max/min 和四类边界路径；尤其观察新增 64 位计数/比较及中断控制是否形成新的最差路径。5 ns 不达标先保留诊断，不自动降频或加例外。
4. **电气与时序**：DC/PT `constraint_violations.rpt`、setup/hold、capacitance/slew、fanout、clock connectivity；需要同时解释工具检查差异和实际网络。
5. **记录结论**：归档选定报告、明确 reset/常量条件的影响；通过后建立 M5 新范围基线，作为 S8/GShare 的输入。

当前没有本地准备阻塞。尚待的是用户在服务器执行并回传真实 EDA 结果；没有这些结果，不能将 S7、M17 或 M5 总验收标为完成。
