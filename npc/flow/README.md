# NPC DC/PT baseline flow

> M5 S1（2026-10-20）：当前 RTL 已升级，M4 的 `ysyx_core_axi4lite` scope 不再存在。
> 本页原命令/配置用于历史复现，请使用 M4 对应 Git revision；当前新建 run 的 preflight 会明确拒绝旧 scope。
> 已存在 run 的 `inspect` 不受影响。新的 CPU + router/CLINT/wrapper scope 与 SDC 在 M5 S7 建立。


M4 S2 provides a small **wire-load DC → pre-layout PT** flow for
`ysyx_core_axi4lite`: Core + IFU/LSU adapters + Arbiter. All commit/monitor ports remain in scope. M4 S2.5 reduces the register file to
16 entries and removes M arithmetic; illegal encodings raise cause 2.
No parameter overrides: `PC_RST=0x80000000`, `IFQ_DEPTH=2`.
No B1 SRAM/peripherals, Xbar, memory compiler, PnR, SPEF, GLS or PTPX dependency.

`00_indata/filelists/core.f` contains 16 ordered SystemVerilog sources, relative to **npc/**.
The primitive also includes `vsrc/gnrl/ysyx_global.sv`. Implementation defines
only `SYNTHESIS`; normal NPC simulation separately enables `NPC_SIM_DPI`.
GPR x1–x15 reset to zero and x0 reads zero. See the current
[ISA/CSR contract](../../docs/notes/post-c/4-pre-soc-signoff/2.5-isa-contract.md);
S1 and first-synthesis reports describe the historical 32-entry/M implementation.

## 目录与输入

```text
npc/flow/
├── 00_indata/
│   ├── configs/         # design/site 配置
│   ├── constraints/     # SDC
│   ├── filelists/       # 引用 npc/vsrc 的 RTL 清单
│   └── DB/STD_NEW/      # 本地/服务器拷入的工艺 DB，Git 忽略
├── 01_common/           # driver、配置加载、共享 Tcl
├── 02_syn/              # DC probe 与综合
├── 03_sta/              # PT 分析
├── 04_tests/            # 本地 mock / 约束契约检查
└── build/<RUN_ID>/      # 每次运行的快照、日志、报告、网表和中间文件
```

flow 的配置和外部输入统一放在 `00_indata`；RTL 的唯一维护位置仍为
`npc/vsrc`，通过 filelist 引用，在启动 run 时复制完整源闭包。
快照仅收集维护的配置/脚本/源码，排除 `build` 和 DB 数据目录；DB 只记录路径与 hash。

## 新手阅读顺序

初次接触综合/STA，建议按以下顺序阅读。各脚本已补充中文阶段说明、关键命令含义和手册页码；先理解输入输出，再读具体检查实现。

| 阅读顺序 | 文件 | 重点问题 |
| --- | --- | --- |
| 1 | [Makefile](Makefile) | 哪些入口在本地检查，哪些会启动服务器 EDA？新 run 与已有 RUN 怎样区分？ |
| 2 | [设计配置](00_indata/configs/npc_core.tcl)、[site 配置](00_indata/configs/site.example.tcl) | 什么是 top、PVT/Vt、周期、slew/load？哪些数值是假设，哪些必须读库确认？ |
| 3 | [共享初始化](01_common/setup.tcl) | target/link/synthetic 库各做什么？`.db` 与 WLM 如何参与分析？ |
| 4 | [SDC](00_indata/constraints/core.sdc) | 时钟和 I/O min/max 怎样定义时序预算？早期 reset 例外排除了哪些检查、何时撤销？ |
| 5 | [DC 综合](02_syn/run.tcl) | analyze、elaborate、link、compile 分别完成什么？`.v`、`.ddc`、`.sdc` 各交给谁？ |
| 6 | [PT 分析](03_sta/run.tcl) | setup/hold、arrival/required time、slack、WNS/TNS、coverage 怎样解读？ |
| 7 | [Python driver](01_common/flow.py) | 快照/hash 如何防止误用旧结果？为什么进程退出 0 还不够？ |
| 8 | [测试](04_tests/test_flow.py) | mock 能验证脚本哪些行为，又有哪些结论必须等待真实工具？ |

这条流程止于单元映射与 pre-layout 时序分析。布局决定单元位置，CTS 构建时钟树，布线与提取提供实际互连寄生；这些后端步骤尚未执行，因此当前假设下的 timing 不能称为 post-route sign-off。

## Local checks

Requires Python **3.9+** and Tcl **8.6**. No EDA executable or PDK is needed:

```bash
make -C npc/flow check test
```

`check` validates config/source closure, Tcl completeness and the SDC object
contract. `test` exercises failure handling/provenance with explicitly fake tools,
and sources the actual Tcl scripts against a mock command surface. Passing these
checks **does not establish DC/PT command compatibility, library/license readiness,
synthesis, STA, or timing PASS**. Current functional evidence includes the S2.5
ISA contract and the [S6 final local regressions](../../docs/notes/post-c/4-pre-soc-signoff/6-reproduction.md#2-本地最终回归本次重新执行的证据).

## Server execution

First enter the server environment that provides DC/PT and licenses. Do not run
these stages locally to reproduce ref-flow. Run from this repository's root:

```bash
cp npc/flow/00_indata/configs/site.example.tcl npc/flow/00_indata/configs/site.local.tcl
make -C npc/flow probe SITE=00_indata/configs/site.local.tcl RUN_ID=lib-probe
```

The example selects one RVT/TT DB under `00_indata/DB/STD_NEW/`, resolving the
path relative to the configuration file. External absolute DB paths also work.
Set executable paths to the installed
versions if needed. `probe` needs only DC and the DB; it writes version/library
reports without synthesizing. Inspect `npc/flow/build/lib-probe/reports/probe/environment/`.

Version reporting reads `get_app_var sh_product_version`; DC V-2023.12-SP5
rejected the earlier `version` command. Library reports use `report_lib` for
technology libraries (including `gtech`) and `report_synlib` for DC's loaded
`.sldb` libraries (currently `standard.sldb`). These are different library types,
so replacing every `report_lib` with `report_synlib` would be incorrect.
An error inside `redirect` can appear in the report even if DC exits 0 and writes
`complete.txt`; inspect the reports as well as the log. The driver rejects these
errors. After syncing a script fix, use a new `RUN_ID` or explicitly clean the old run.

Update `site.local.tcl` with the actual `library_name`, `operating_condition`,
PVT/Vt and `area_unit`. Verify **ns** time and **pF** capacitance units against the
library; other units require explicit conversion of the design constraints.
Then set `library_reviewed=1`. The supplied example intentionally has this flag
at 0; its candidate library name and operating condition still require review,
so it cannot silently become a measured NPC corner based only on a filename. Private `*.local.tcl` files are ignored.

```bash
make -C npc/flow preflight SITE=00_indata/configs/site.local.tcl
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-200mhz
# Or split DC and PT without regenerating inputs:
make -C npc/flow synth SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-200mhz-split
make -C npc/flow sta RUN=build/core-tt-200mhz-split
make -C npc/flow inspect RUN=build/core-tt-200mhz
```

当前默认周期为 **5 ns / 200 MHz**，数据 I/O 的 min/max 为 0.2/2.0 ns；
reset 无 input delay，仅按当前 scope 设置精确 false path。
[04 实验](../../docs/notes/post-c/4-pre-soc-signoff/synthesis-results/04-200mhz-baseline/README.md)
已建立该条件下的 S3 面积/数据时序基线。
[S6 复现与交接](../../docs/notes/post-c/4-pre-soc-signoff/6-reproduction.md)包含最终回归、
服务器新 run 命令及复现对照标准；05 已独立复现 04，
[M4 本轮验收完成](../../docs/notes/post-c/4-pre-soc-signoff/signoff.md)。后续复现继续使用新目录，不覆盖历史 run。

`preflight` checks paths/config/tool executability, not license checkout or Tcl
command support. `probe`/`synth`/`all` always create a **new** run; existing IDs
are rejected. An attempted stage cannot be overwritten. After correcting a
failure, choose a new ID or explicitly clean that run. No automatic cleanup,
resume or old-netlist fallback.
Use `RUN_ROOT=/absolute/server/path` to place outputs elsewhere; `sta`/`inspect`
then take that run's absolute path. Tcl execution uses the copied NPC source tree,
so relative include paths continue to work. Do not move a live run: its absolute
path is part of the manifest. If the driver changes, both `sta` and `inspect` require the archived
`inputs/npc/flow/01_common/flow.py` against the original run (older snapshots use
`inputs/npc/flow/common/flow.py`).

### 清理与重跑

```bash
make -C npc/flow clean RUN_ID=lib-probe
make -C npc/flow probe SITE=00_indata/configs/site.local.tcl RUN_ID=lib-probe
```

`clean` 删除指定 run 的全部快照/日志/报告/网表，之后允许复用同一个 ID；
需要保留诊断或对比证据时使用新 ID。它不依赖 SITE、EDA 或 DB 可用性。
默认只作用于 `npc/flow/build/<RUN_ID>`；使用自定义 `RUN_ROOT` 时，清理也必须传入同一值。
不指定 ID、路径穿越、run 符号链接、manifest 缺失/不匹配、阶段状态为 `RUNNING`
都会拒绝清理。目标不存在则成功返回，不删除其他 run 或 `00_indata`。
异常杀进程留下 `RUNNING` 时，需先确认进程停止并核对状态，不能直接删除运行目录。

旧布局升级：将服务器私有 `configs/site.local.tcl` 移到
`00_indata/configs/site.local.tcl`，将自备 DB 放到 `00_indata/DB/STD_NEW/`，并更新
`target_db` 的绝对路径；不要覆盖已有 site 中核对过的设置。
旧 `npc/build/flow/` run 保持原位，因为 manifest 绑定绝对路径；如需明确删除旧 run，使用
`make -C npc/flow clean RUN_ROOT=../build/flow RUN_ID=<旧ID>`。
新 run 默认生成在 `npc/flow/build/`，不迁移或改写历史产物。

If startup reports `The  script is not supported.`, inspect
`manifest.json → stages.probe.argv[0]` and the tool symlink. Some launchers dispatch
by the invocation name (`dc_shell`/`pt_shell`); replacing that symlink with its
resolved target can break startup before the probe Tcl runs. The driver preserves
the invocation path while making it absolute; hashes still read the target's
contents. After updating an older driver, use a new ID or explicitly clean the
failed run before retrying; existing runs retain their original inputs.

## Constraints and models

`00_indata/configs/npc_core.tcl` freezes the **pre-layout baseline** 5 ns target (200 MHz), not a
measured silicon frequency or a demonstrated Fmax. Inputs and outputs have 0.2/2.0 ns min/max delay;
setup/hold uncertainty is 0.2/0.05 ns; clock/input transition 0.1 ns; output load
0.01 pF; source latency min/max 0 ns. All observation outputs are included.
These are explicit initial interface assumptions, not extracted from a board or
SoC. The accepted S3 run satisfies timing under these assumptions. Failed runs
remain diagnostic records; frequency exploration is a separate configuration/run
with the other assumptions held fixed.

For early core-only evaluation, `set_false_path -from [get_ports rst_n]` defers
reset timing until the actual SoC/reset source and IO contract are defined. The old
`reset_min/reset_max` configuration keys and reset input delays are removed; update
custom design configs accordingly. Recovery/removal and reset-to-data/output paths
are excluded. This does not prove pulse-width safety or guarantee that untested
checks disappear. Keep coverage and all diagnostic reports for review.
No reset case analysis, RTL reset removal or internal synchronizer is added.
The timing clock stays ideal; uncertainty does not model CTS. See the explicit
[reset TODO and scope](../../docs/notes/post-c/4-pre-soc-signoff/reset-timing-todo.md).
Historical runs retain their frozen configurations; use a new RUN_ID.

The single selected library is shared by DC and PT. Automatic area-based wire
load selection is disabled and mode is `top`. `wire_load_model=library_default`
is an **explicit policy**: inspect the actual default model in library/design/
wire-load reports. If the library has no model, do not relabel the result as a
physical interconnect estimate. Alternatively specify an exact named library
model, applied identically in both tools. The current example is not a claim of
zero RC or of a particular WLM name. No SPEF or C906 wire model is substituted.

DC uses ordinary `compile -map_effort medium`, without `compile_ultra`, gating,
scan, UPF, physical optimization or additional DesignWare Foundation libraries.
The current policy omits the explicit
`set_fix_multiple_port_nets -all -buffer_constants` request; the 66 min-capacitance
violations from experiment 03 no longer appear in accepted run 04. Feedthrough assigns may remain;
ordinary timing-driven buffering is still allowed. Electrical checks stay enabled.
See [the original diagnostic procedure and acceptance checks](../../docs/notes/post-c/4-pre-soc-signoff/s3-buffer-check.md).
The accepted baseline sets **DC-only `max_fanout 32` on the synthesis
top**, replacing the extra 0.075 pF capacitance target. This is a sum of library
`fanout_load` weights, not necessarily 32 pins. All library capacitance and slew
limits remain applicable to ordinary data/control nets. DC explicitly disables
clock-network DRC fixing with `set_auto_disable_drc_nets -on_clock_network true`;
the shared SDC retains ideal-clock timing. Pre/post compile checks require the
top fanout attribute to remain present. The clock source net's
`auto_disable_drc_nets` flag is an optional query: DC 2023 reports it unavailable,
so the report records `UNAVAILABLE`, not a verified true/false result. Check the
mapped clock connectivity; failures of the policy command itself still stop the flow.
PT continues to check the original SDC and library rules. Other high-fanout control
nets, including reset, are subject to this optimization policy. Run 04 has no
DC/PT constraint violations; S6 checks reproduction against its area, timing and
coverage rather than treating the policy alone as proof of passing.
See [fanout policy and clock handling](../../docs/notes/post-c/4-pre-soc-signoff/s3-capacitance-check.md#7-改用-max_fanout-32-并排除时钟-drc-修复).
The built-in standard synthetic library supports HDL operators. Server mapping
and resource reports must confirm that the large arithmetic really maps.
PT reads `outputs/core.v` and replays the **same frozen design SDC/config** as DC;
DC's exported `dc.sdc` is also retained/hashed for cross-checks. PT does not source
DC-specific environment commands from that export.

## 报告目录与阅读顺序

2026-10-18 起，新 run 的报告按 `reports/<stage>/<category>/` 分类；stage 为
`probe`、`syn`、`sta`。日志仍放在 `logs/`，网表/DDC/导出 SDC 仍放在 `outputs/`。

`constraints.rpt` 改为 **`checks/constraint_violations.rpt`**：它来自
`report_constraint -all_violators`，列出当前生效约束下的时序及电气违例，
不是约束定义或完整约束清单。设计约束本身见冻结输入 `inputs/` 和导出 `outputs/dc.sdc`。

实际例子：`core-tt-10ns-rv32e-nom` 的 PT 旧版 `constraints.rpt` 有 66 条
`min_capacitance` 电气违例，因此完整报告不应命名为 `timing_violations.rpt`。

| 分类 | 文件 | 阶段与用途 |
| --- | --- | --- |
| `environment/` | `version.rpt`、`library_*.rpt` | probe/DC/PT：工具版本、实际加载库 |
| `environment/` | `design.rpt`；PT 另有 `units.rpt`、`wire_load.rpt` | 核对设计环境、单位与互连模型 |
| `summary/` | `qor.rpt` | DC：整体 QoR 快速概览 |
| `checks/` | `check_design_pre.rpt`、`check_design_post.rpt` | DC：综合前后结构检查 |
| `checks/` | `high_fanout.rpt` | DC：工具高扇出阈值、网络名称和连接明细 |
| `checks/` | `disable_timing.rpt` | PT：禁用时序弧，供定位 PTE-003 原因 |
| `checks/` | `check_timing.rpt`、`constraint_violations.rpt` | DC/PT：分析完整性检查与违例列表 |
| `checks/` | `coverage.rpt`、`coverage_untested.rpt` | PT：met/violated/untested 及未测试原因 |
| `timing/` | `timing_max.rpt`、`timing_min.rpt` | DC/PT：max/min 代表路径，max_paths=20 |
| `timing/` | `Reg2Reg_{max,min}.rpt`、`In2Reg_{max,min}.rpt`、`Reg2Out_{max,min}.rpt`、`In2Out_{max,min}.rpt` | PT：四类边界路径，各 max_paths=10 |
| `timing/` | `metrics_max.tsv`、`metrics_min.tsv` | PT：按违例端点去重的 WNS/TNS/数量，不从 Top-20 求和 |
| `area/` | `area.rpt`、`resources.rpt`、`references.rpt` | DC：面积、运算资源、映射单元 |
| `power/` | `power_status.txt`、可选 `power_attempt.rpt` | DC：是否评估及原始功耗尝试报告；默认关闭 |

例如 DC 的违例文件为：
`npc/flow/build/<RUN_ID>/reports/syn/checks/constraint_violations.rpt`。
PT 则为同一 run 的 `reports/sta/checks/constraint_violations.rpt`。
仅创建对应阶段需要的分类目录；`complete.txt` 是机器读取的完成标记，保留在阶段根目录。

建议先读 DC 的 `summary/qor.rpt` 看概况，再读 `checks/` 确认有没有漏检、哪些检查失败，
随后进入 `timing/` 解释具体路径；需要定位面积或核对模型时分别查看 `area/`、`environment/`。
PT 从 `checks/` 与 `timing/metrics_*.tsv` 开始。报告存在或 WNS=0 均不能代替 coverage 审查。

PT 多路径默认只列负 slack，全部满足时报告为空；现已在全局/四类
代表路径查询中加入 `-slack_lesser_than 1.0e30`，包含正常正裕量路径。该阈值只筛选
报告，不修改 SDC；WNS/TNS 查询仍只枚举负 slack。DC/PT 的 timing/constraint 报告
使用 6 位小数。改动已通过本地 mock，并在服务器 `core-tt-5ns-baseline` 中生成完整报告；命令依据见
[S3 重跑说明](../../docs/notes/post-c/4-pre-soc-signoff/s3-rerun.md)。

`checks/high_fanout.rpt` 用 `all_high_fanout -nets` 按 DC 实际阈值查询整个层次，
逐个调用 `report_net -connections -verbose`。它是综合后快照，不保证保留优化中间态
曾出现的每个高扇出网；不穿透 buffer/inverter 合并扇出，也不把 clk/reset 预先豁免。
完整服务器交接及基线候选审查见 [S3 重跑说明](../../docs/notes/post-c/4-pre-soc-signoff/s3-rerun.md)。

DC/PT 均新增 `checks/lsu_enable_capacitance.rpt`：从 LSU 请求寄存器 E 引脚反查
实际网络，记录各使能分支的驱动/负载、原始 `report_net`、可用的库电容限制及
CCS 属性。不绑定 U13/n3，不修改 RTL、SDC、映射策略或模型开关；缺失属性明确
标为 UNAVAILABLE，无匹配 E 引脚时要求审查网表。该报告是必需产物并纳入 hash。
具体字段、解释边界及新 run 命令见 [DC/PT 电容对照](../../docs/notes/post-c/4-pre-soc-signoff/s3-capacitance-check.md)。

**旧 run 不迁移、不重命名。** 首次综合归档继续使用原来的扁平目录。目录属于 run 的冻结契约；
更新 flow 后，以新 RUN_ID 生成分类报告。检查旧 run 或继续其 STA 时使用该 run 自带的 runner：

```bash
python3 npc/flow/build/<RUN_ID>/inputs/npc/flow/01_common/flow.py \
  inspect --run npc/flow/build/<RUN_ID>
# 继续旧 run 的 STA 时，将 inspect 替换为 sta。
```

检查器与 manifest 递归记录分类目录内的产物，包括失败阶段和可选功耗的诊断文件；
子目录中的报告被修改也会触发 hash 校验失败。报告分类本身只调整组织与命名；
诊断增强及随后的综合裕量实验见上文；后者会改变综合优化目标，待服务器验证。

## Evidence and failure semantics

Each run contains `inputs/`, `logs/`, `reports/`, `outputs/`, `work/`, `launch/`
and `manifest.json`. Inputs include RTL/include/filelist, copied flow code,
original configs, effective config, Git HEAD/status/dirty patch and hashes.
Server DB and executable hashes are recorded without copying the PDK. Version
reports capture the tools actually launched. Netlist/SDC/DDC and reports are hashed
before PT can consume them; mutation fails both before and after tool execution.

DC startup files discovered in HOME/install/SYNOPSYS are hashed; the launch cwd
is empty and isolated. PT uses `-no_init`. DC startup scripts may themselves source
other files: review any site customization and add its dependencies to the run
record for S3. This is reproducible input accounting, not a hermetic EDA container.
No script changes HOME or license variables.

A successful shell exit alone is insufficient: the driver checks completion
markers, required nonempty reports, error diagnostics, mapped positive cell area
and netlist top. DC checks link/design/unmapped cells and unexpected latches.
PT emits max/min timing, four path classes, analysis coverage, unconstrained-check
diagnostics and worst-negative-slack/TNS/violating-endpoint metrics. TNS deduplicates
endpoints and refuses a truncated path collection. WNS is clamped to 0 when no
negative paths exist; it is not the best achievable period.

Execution can be `COMPLETE` while assessment is `TIMING_FAIL`, `CONSTRAINT_FAIL`
or `REVIEW_REQUIRED`. `reported_constraint_violation_rows` counts printed
`(VIOLATED...)` rows, including electrical constraints; it is not a deduplicated
timing-endpoint count. A nonzero count yields `CONSTRAINT_FAIL` unless timing
failure already takes priority. Zero rows never imply automatic constraint PASS.
A negative baseline is retained for analysis, not discarded or called timing PASS.
Unknown coverage format, missing outputs and tool errors fail execution. Warnings,
untested checks (including constants), loops, disabled/unconstrained paths, clock
and DRV coverage require S3 review; **this driver never awards automatic signoff
PASS**, even for zero WNS. Raw reports take precedence over the small summary.

Optional `power_enable=1` attempts DC power reports with input activity 0.1 toggles
per core clock period and static probability 0.5; clock is 2 toggles/period,
reset inactive with zero toggles/probability 1. Internal activity is default or
propagated, not workload-derived. The attempt runs after netlist/SDC export,
without changing timing constraints, and is separately logged. Unsupported
commands/models are `NOT_EVALUATED` and do not block area/timing; apparently
successful estimates still require unit/activity/coverage review. Default is off.

Design decisions, manual pages, local results and server handoff:
[M4 S2](../../docs/notes/post-c/4-pre-soc-signoff/2-flow.md).
