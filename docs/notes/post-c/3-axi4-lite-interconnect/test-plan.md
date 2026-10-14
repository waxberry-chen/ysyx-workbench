# M3 验证与验收矩阵

> 2026-10-14；状态：S1 Arbiter 子集已实现并通过，其余模块/系统测试待推进。
> 设计契约见 [plan.md](plan.md)，实际执行记录写入 [dev-log.md](dev-log.md)；本文件不记录未经运行的 PASS。

S0 已复测 M2 最小基线，见 [0-baseline.md](0-baseline.md)。S1 结果见 [1-arbiter.md](1-arbiter.md)。T01–T15 的实施/执行状态维护在 [test-status.csv](test-status.csv)；`ARBITER_PASS` 仅指 S1 的模块子集，legacy 或 standalone 证据不等于 M3 系统验收。

## 1. 验证对象与责任

分三层验证，避免 CPU workload 的有限协议行为留下空洞：

- **模块层**：Arbiter、Xbar、各 slave；独立 driver 主动制造 WVALID 早于 AWVALID、响应反压、reset 等场景。
- **子系统层**：双 master driver + Arbiter + Xbar + RTL slaves，transaction scoreboard 校验路由、数据、错误和副作用。随机延迟注入在协议正确的边界 shim 或 scripted slave 中。
- **真实 Core 层**：现有 adapters + Core + B1 system + AM workload，检查 commit GPR/CSR DiffTest、异常与运行结果。MMIO 被 reference skip 的内容由总线 scoreboard/设备 monitor 验证。

scoreboard 为每个已预留/接受事务记录验证侧序号、owner、type、地址、PROT、AW/W 到达情况、route、预期 data/resp、完成/中止状态。序号不加入 RTL 协议。参考存储逐 byte 更新，地址译码与寄存器预期按规格独立计算，不读取 DUT 的 target/error 来当预期值。

计数区分 reserved、AR、AW、W、完整 write、effect、R/B 完成。reset 后按 epoch 清理未完成项，保留已发生 effect；正常 drain 后应无 outstanding。收到多余 response、错误 owner 或重复 effect 立即失败。

## 2. 需求到测试、断言与覆盖

下表为最低必测集合。`Axx` 为计划中的可执行属性/monitor ID，`Cxx` 为覆盖组 ID；实现时必须将 ID 绑定到实际文件、target 与结果，不能只保留文字。

| 测试 / 需求 | 场景与判定 | 属性 / 覆盖 |
| --- | --- | --- |
| T01 请求与响应稳定 | 对 AR/AW/W/R/B 分别施加 0、1、7、64 周期 stall；VALID/payload 不撤销、不变，响应不会依赖 READY 才出现 | A01 五通道 holding；C01 channel × stall bin |
| T02 仲裁与公平性 | IFU/LSU 同时请求；LSU 分别为 read/write；持续竞争下 owner 顺序符合 RR，只有 owner 能握手，结束后换优先权 | A02 owner/type holding、one-hot grant；C02 winner × contender type × previous owner |
| T03 AW/W 分离 | 上游 AW-first、W-first、同拍；间隔 1/7/64 周期；下游 AWREADY/WREADY 独立；W-first 时到达另一 master 请求仍不切 owner | A03 AW/W 各最多接收一次、B 依赖两者完成；C03 ingress/egress ordering × gap |
| T04 单事务与 response ownership | R/B 长反压时另一个 master 保持请求；read/write 交替、连续同类；响应只回原 owner，槽未释放不接受下一笔 | A04 outstanding ≤1、response requires request；C04 type transitions × owner × response stall |
| T05 路由与地址边界 | 每个 region 的首/末合法 word、前后 word、default 地址；AW 后输入变化、W-first、非 word-aligned 独立 AXI 请求 | A05 target holding、target 未知禁止转发、one-hot destination；C05 master × type × route × boundary |
| T06 错误返回与恢复 | default read/write 返回 DECERR；mapped slave 非法操作 SLVERR；错误 RDATA=0；错误后立即运行正常事务，无死锁；禁止失败 store 副作用 | A06 error-no-effect、resp preserved；C06 master × type × route × response |
| T07 SRAM 与 lane | 全部 16 个 WSTRB，含 sparse/zero；预置参考数据后写读；末 word、read-after-write、随机地址/数据 | A07 byte-write mask、effect once；C07 all strobe values × boundary；adapter 层补 lb/lbu/lh/lhu/lw/sb/sh/sw |
| T08 reset | idle、owner 已预留未握手、AR/AW-only/W-only、AW+W、等待响应、R/B 被反压；reset 后新事务可运行且无旧响应/重复 effect | A08 reset clears control、epoch accounting；C08 state × type × reset；SRAM 不清零、mtime 清零 |
| T09 UART | 连续字符与长 B stall；lane0 一次输出、zero strobe 零输出；非法 strobe/读/保留 offset/IFU 访问出错；reset 前后统计 | A09 tx_event iff successful effect、no replay；C09 access × strobe class × response stall |
| T10 CLINT/AM timer | tick 增长、RDATA 被反压仍稳定、low rollover、high-low-high 重试、reset；写/取指失败；uptime 单调与单位换算 | A10 sampled data stable、mtime progression；C10 half × rollover × stall × operation |
| T11 Core 精确异常 | fetch/load/store 未映射 cause 1/5/7；MMIO fetch、只读写；受控 SLVERR；misaligned cause 4/6 不发 LSU AXI 请求；检查 mepc、正常写回抑制与 trap 后状态 | A11 fault/commit consistency；C11 fault origin × cause；DiffTest ON |
| T12 redirect 并发 | IFU 等待仲裁、AR 已接收等待响应、错误/正常 R 到达同拍发生 redirect；旧 fetch 完成后被丢弃，不进入错误路径 commit | A12 stale response not committed；C12 redirect phase × RRESP |
| T13 子系统随机 | 双 master 随机竞争、地址/数据、独立 AW/W delay、channel stall、错误与 reset；每笔由 scoreboard 比较；停止发新请求后 drain | A01–A10 全开；C01–C10 覆盖汇总、seed 可复现 |
| T14 系统回归 | CPU tests（排除旧 unalign）、add 架构 trace、hello、有限 uptime、yield-os/CSR DiffTest、RT-Thread workload | A11/A12 与协议属性全开；C13 workload × profile × timing configuration |
| T15 静态与交付 | 三个层次 top 的 lint、无新增未解释 warning；生成证据 manifest、架构图与三段波形 | filelist/top/config 完整性；所有 T/A/C ID 可追溯 |

补充规则：

- `T03` 必须同时覆盖 **请求发布顺序** 与 **握手顺序**，仅随机 AWREADY/WREADY 不够。
- `T11/T12` 的错误注入在请求执行前决定拒绝，不能先产生 store 副作用再改 BRESP。错误注入器为 test-only；SRAM 生产逻辑不会随机出错。
- `T08` 不承诺 reset 前已输出字符可撤销；检查 reset 不造成新增或重放事件。测试不能将 reset 与正常响应同时完成的采样规则留给竞争调度决定。
- `T12` 要保留 M2 的 IFU+adapter 定向测试，并新增带 Arbiter 的竞争场景。

## 3. 功能覆盖与前进性

导出 JSON/CSV bin 计数，列出每个测试命中的 T/A/C ID。无 covergroup 支持时使用 SV/C++ monitor counter。验收目标是**必测合法 bin 全命中**，不以随机 seed 数代替覆盖，也不要求盲目全笛卡尔积。

最小必测 cross：

- IFU read 与 LSU read/write 到四条 route；SRAM 成功、UART/CLINT 允许的成功或 SLVERR、default DECERR。IFU write 为结构性不可达。
- AR/AW/W 请求 stall、R/B 响应 stall 分别命中 none/short(1–7)/long(≥64)；read 不要求 B stall，write 不要求 R stall。
- 上下游 AW-first/W-first/same，以及 target-known/unknown 时的 W 缓存。
- 合法 `OKAY`、`SLVERR`、`DECERR`；本系统不产生 EXOKAY，M2 adapter 的非 OKAY 错误映射回归保留。
- SRAM 所有 16 个 strobe；UART lane0/zero/非法 lane；CLINT 两个半字与 rollover。
- 每类事务的 reset 关键阶段、竞争获胜者与 redirect 关键阶段。

自然不可达 bin 标 N/A 并写理由（例如 IFU write），未激励的合法 bin 是 hole，必须补定向用例或明确延期，不能改成 N/A。代码覆盖可补充，但不替代功能覆盖。

前进性采用有界仿真与明确假设：每个受控 channel 最多连续 stall 64 周期，driver 获得服务后 64 周期内提供缺失 AW/W，slave 内部延迟不超过 64 周期。在该配置下，单事务 watchdog 初设 4096 周期，持续竞争请求至完成初设 8192 周期；实现时按状态/各层缓冲推导并收紧，不能为掩盖 hang 任意放大。

另做超过上述上限的合法长 stall 定向测试，使用匹配该用例的 watchdog。无限 READY=0 时只检查 holding/safety，不声称有界完成。无死锁与公平性结论必须附环境假设。

对 owner/target holding、response 唯一归属、AW/W 汇合可尝试 bounded formal。记录 DUT 参数、assumptions、工具版本、深度与结果；bounded PASS 不表述为无界证明。工具不可用时保留可仿真的 SVA 与定向反例回归，formal 状态为待验。

## 4. 回归规模与终止条件

| 层级 | 首版验收规模 | 成功条件 |
| --- | --- | --- |
| L0 定向 | T01–T12 全部必测场景 | assertions/scoreboard 全通过、必测 bin 命中 |
| L1 fabric random | 固定 seeds 1–10，每 seed 至少完成 1000 笔事务；常规随机 gap/latency 0–7，另有 64 周期定向 stall | 无 mismatch、watchdog、重复 effect；末尾 drain 完成；reset aborted 单列且不计入完成笔数 |
| L2 CPU | 当前 34 项成功路径 CPU tests，另跑 cause 1/4/5/6/7；固定 add 架构 trace | DiffTest ON，精确 PASS 数与 GOOD TRAP；不能只看 make 退出码 |
| L2 随机系统 | add、bubble-sort 各 seeds 1–10，记录 shim 配置 | 每个 workload/seed 都正常结束；不把此结果说成全部 CPU tests 都做了随机回归 |
| L3 hello | 默认参数与 `I-love-ysyx` | 输出逐字检查、GOOD TRAP、UART effect 数与预期字节数一致 |
| L3 uptime | 有限次采样（至少 100 次）、跨 rollover 定向测试 | 值单调、换算正确、结束标志；不以看到 GMT 字样代替计时正确性 |
| L3 yield-os | 至少观察 100 次 A/B 交替及 CSR DiffTest；设置周期上限 | 达到有意义进度且无 mismatch/assertion；只有 timeout 不算 PASS |
| L3 RT-Thread | 固定本地 BSP revision/config；建立无 RX、协作 yield 的双线程 workload，各执行至少 100 次有标记的迭代并检查局部状态/heap 使用 | 明确完成标志、上下文切换与 GPR/CSR DiffTest 通过；启动 banner 不算通过，M3 不宣称 timer-preemptive scheduling |
| L5 lint | Core、含 Arbiter wrapper、B1 top | 新增 warning 清零或逐条解释；无 latch/组合环/未驱动控制 |

RT-Thread workload 在 S5 开始时冻结源码、迭代数与结束方式；若既有应用无法产生可检查的有限结束，添加小型测试入口。该任务属于 M3 必测出口，尚未执行不能标记 milestone 完成。完整 timer interrupt 属于 M5。

系统周期预算在确定性基线首次运行后记录，再用于回归；host wall-clock timeout 仅是资源保护。系统随机测试预算应留有解释得通的余量，不能仅以原先“10 秒没崩溃”判定通过。

## 5. 构建与命令契约

legacy 可用入口（执行范围以各阶段报告为准）：

```bash
make -C npc axi4lite-signoff
make -C am-kernels/tests/cpu-tests ARCH=riscv32e-npc ALL=bubble-sort run
make -C rt-thread-am/bsp/abstract-machine ARCH=riscv32e-npc run
```

最后一条是从当前 BSP Makefile 推导的入口，未确认构建成功；BSP 依赖 `files.mk`、`rtconfig.h` 和环境变量，干净环境必要时先按该 BSP 的 `init` 目标生成配置，并记录工具/生成输入。

以下均为 **拟新增目标，当前不能直接运行**：

```text
make -C npc b1-xbar-test
make -C npc b1-slaves-test
make -C npc b1-directed-regress
make -C npc b1-random-regress
make -C npc b1-system-regress
make -C npc b1-signoff
```

S1 已实现并运行的入口：

```bash
make -C npc b1-arbiter-lint
make -C npc b1-arbiter-test
```

后者内含 lint、定向/reset 和 10 个固定 seed 的 standalone 随机测试，导出 `coverage.csv`，默认路径为 `npc/build/b1-arbiter-test/`。这些结果尚不覆盖 Xbar、RTL slaves 或 Core 集成。

`b1-signoff` 依次调用 lint、定向、随机、系统回归并汇总 coverage；内部显式选 b1 profile。实现时可拆分目标，但必须保持一条聚合入口和可单独复现的子目标。M2 旧入口继续运行 legacy 环境，其 PASS 不能代替新 RTL system 的验收。

profile 传播示意（待实现）：`make ... ARCH=riscv32e-npc NPC_PLATFORM=b1 NPC_SRAM_BYTES=0x100000 run`。同名参数应贯穿 AM、NPC 和 RTL，具体代码落地后更新本文。

## 6. 性能与证据归档

add 的旧架构 hash 为 `bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284`，来自 M2 报告。仅在相同 ELF/初始状态且容量适配未改变程序架构行为时比较该 hash；AM heap 参数变化可能改变初始化指令与寄存器值，必须先说明差异。优先让 legacy/b1 运行同一份已证明地址范围合法的测试镜像做架构等价比较，不能为了 hash 相同隐瞒不同程序。

不固定 IF 事务数（投机取指随时序变化）；通过分层守恒计数与 outstanding 解释差额。固定 add、bubble-sort、hello 的镜像、确定性 memory latency、编译配置，报告 cycles/commits/CPI、仲裁等待与现有 stall；M2 与 M3 不能仅凭相同 seed 声称等时序性能对比。

每轮验收保存：

- RTL/脚本 commit、未提交 patch 标识、workload ELF/bin hash、工具与 NEMU/BSP revision。
- profile/top/filelist、SRAM 容量、mtime 频率、seed、各 shim 延迟策略、停止/drain 条件、DiffTest 开关。
- 每个 T/A/C ID 的状态与日志位置、覆盖 bin 与 hole、失败 seed 的最小复现和波形。
- 结果摘要、周期/事务/effect 计数、异常 cause/mepc、限制与下一步。

构建日志先落在独立的 B1 build 子目录；正式验收时把摘要入库，并将原始日志/FST 放入可定位的长期归档，记录 hash。仅有可随 clean 删除的 build 路径不满足长期证据要求。尚未运行标“待验”，工具不适用标“N/A + 原因”，不可用工具不伪装成通过。

M3 功能与协议验收通过后，综合/STA、四值和网表 smoke 在 M4 单独给结论；有条件可提前试跑，结果不得与本阶段仿真验证混为同一 PASS。
