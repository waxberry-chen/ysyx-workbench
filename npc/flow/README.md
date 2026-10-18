# NPC DC/PT baseline flow

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
| 4 | [SDC](00_indata/constraints/core.sdc) | 时钟和 I/O min/max 怎样定义时序预算？为什么 reset 不能直接全设 false path？ |
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
synthesis, STA, or timing PASS**. RTL is unchanged in S2; S1 regressions remain the
functional evidence.

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
reports without synthesizing. Inspect `npc/flow/build/lib-probe/reports/probe/`.

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
at 0 and an empty operating condition, so it cannot silently become a measured
NPC corner based only on a filename. Private `*.local.tcl` files are ignored.

```bash
make -C npc/flow preflight SITE=00_indata/configs/site.local.tcl
make -C npc/flow all SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-10ns
# Or split DC and PT without regenerating inputs:
make -C npc/flow synth SITE=00_indata/configs/site.local.tcl RUN_ID=core-tt-10ns-split
make -C npc/flow sta RUN=build/core-tt-10ns-split
make -C npc/flow inspect RUN=build/core-tt-10ns
```

`preflight` checks paths/config/tool executability, not license checkout or Tcl
command support. `probe`/`synth`/`all` always create a **new** run; existing IDs
are rejected. An attempted stage cannot be overwritten. After correcting a
failure, choose a new ID or explicitly clean that run. No automatic cleanup,
resume or old-netlist fallback.
Use `RUN_ROOT=/absolute/server/path` to place outputs elsewhere; `sta`/`inspect`
then take that run's absolute path. Tcl execution uses the copied NPC source tree,
so relative include paths continue to work. Do not move a live run: its absolute
path is part of the manifest. If the driver changes, invoke the archived
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

`00_indata/configs/npc_core.tcl` freezes an **exploratory** 10 ns target (100 MHz), not a
measured operating frequency. Inputs and outputs have 0.2/2.0 ns min/max delay;
setup/hold uncertainty is 0.2/0.05 ns; clock/input transition 0.1 ns; output load
0.01 pF; source latency min/max 0 ns. All observation outputs are included.
These are explicit initial interface assumptions, not extracted from a board or
SoC. S3 may produce a negative-slack baseline; frequency exploration is a separate
configuration/run with the other assumptions held fixed.

Reset is asynchronous assert, externally synchronized deassert. Its release has
0.2/2.0 ns input delay, retaining recovery/removal and combinational reset-to-output
paths. No reset false path, case analysis, multicycle, propagated clock or derate
is inserted. This top has no internal reset synchronizer. The timing clock stays
ideal; uncertainty does not model CTS.

The single selected library is shared by DC and PT. Automatic area-based wire
load selection is disabled and mode is `top`. `wire_load_model=library_default`
is an **explicit policy**: inspect the actual default model in library/design/
wire-load reports. If the library has no model, do not relabel the result as a
physical interconnect estimate. Alternatively specify an exact named library
model, applied identically in both tools. The current example is not a claim of
zero RC or of a particular WLM name. No SPEF or C906 wire model is substituted.

DC uses ordinary `compile -map_effort medium`, without `compile_ultra`, gating,
scan, UPF, physical optimization or additional DesignWare Foundation libraries.
The built-in standard synthetic library supports HDL operators. Server mapping
and resource reports must confirm that the large arithmetic really maps.
PT reads `outputs/core.v` and replays the **same frozen design SDC/config** as DC;
DC's exported `dc.sdc` is also retained/hashed for cross-checks. PT does not source
DC-specific environment commands from that export.

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

Execution can be `COMPLETE` while assessment is `TIMING_FAIL` or `REVIEW_REQUIRED`.
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
