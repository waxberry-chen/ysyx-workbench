# NPC Core Microarchitecture Refactor Plan

本文给出从当前集中式多周期 NPC 到“可接入 SoC、且仍可继续增量优化”的实施计划。计划吸收 [`core-architecture-study.md`](../../../ref-design-src/core-architecture-study.md) 对参考核的结论，但不复刻参考核的产品特性；B1 总线要求仍以 [`1.7.md`“总线视角下的处理器设计”](../../../misc/ysyx/docs/2306/basic/1.7.md#总线视角下的处理器设计) 为准。

> 计划基线（2026-09-20）：`ea347e2`。当前 NPC 已具备持久化 instruction transaction、随机 request/response backpressure、commit 驱动 DiffTest/Itrace，以及可运行 CPU tests、AM 基本程序和 C6 trap/context workload 的功能基础；data access 仍由 core 内部 DPI RAM 完成，控制仍集中在 `ysyx_main_fsm`。

## 1. 最终决策

SoC 接入前，将 NPC 重构为：

> **RV32E、单发射、顺序提交、弹性前后端、单笔 data transaction、集中 commit/redirect 的小型处理器。**

它不强求教科书式五级流水，也不把参考核的全部复杂度搬进来。目标是先稳定以下边界：

- frontend 只负责 PC、取指 transaction、instruction queue 和 redirect 后的失效处理；
- backend 只负责译码、执行、顺序等待和 architectural commit；
- LSU 独立拥有 load/store transaction，backend 不感知 memory latency；
- IFU/LSU 分别作为 AXI4-Lite master，经 Arbiter 合并为 core 的一个对外 master；
- commit、redirect、exception 是全核统一事件，不散落在各模块中；
- harness 只观察 commit/architectural state，不依赖内部流水级划分。

这里的“成熟”指**模块责任、协议边界和恢复语义稳定**，而不是功能堆满。完成本计划后，cache、BPU、乘除法、多 outstanding 等应能作为局部增量加入，而无需再次推翻 core/SoC 边界。

## 2. 从参考核吸收什么

| 参考核机制 | NPC 决策 | 原因 |
| --- | --- | --- |
| IFU、EXU、LSU、BIU 各自拥有局部握手状态 | 采用 | 消除一个全局 FSM 对所有延迟的耦合 |
| instruction context 随 stage 保存 | 采用 | 保证 PC、inst、预测信息和异常始终属于同一条指令 |
| 单发射、弹性流水 | 采用简化版 | 每级只在 `valid && ready` 时转移，允许任意级停顿 |
| fetch queue + execution op buffer | 各采用 1～2 项小容量 storage | 形成真实的前后端解耦，不追求深流水 |
| 统一 commit、flush 和 exception recovery | 采用 | 保证精确状态更新和 DiffTest 对齐 |
| LSU/BIU 保存 transaction owner | 采用 | response 不能靠当前组合地址重新判断归属 |
| GShare BPU | 预留 metadata，后续独立加入 | 有工程展示价值，但不应阻塞基本重构和 B1 |
| OITF/scoreboard、多 outstanding | 暂不采用 | 当前长延迟指令阻塞 backend，不需要追踪多条未完成指令 |
| ICB、LBIU、NICE、PMP、AMO、cache ties | 不采用 | 属于参考产品协议或当前阶段之外的功能 |
| CLIC | 不采用 | B1 当前只需最小 CLINT；中断控制器以后按 SoC 规范决定 |

参考核最值得学习的是“**状态归属于产生和消费它的局部模块**”，而不是模块名称或代码层次。

## 3. 目标结构

```text
                         ysyx_core
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌──────────────── Frontend ────────────────┐                │
│  │ PC/redirect -> IFU transaction -> 2-entry IFQ             │
│  └──────────────────────┬───────────────────┘                │
│                         │ instruction context v/r             │
│                         ▼                                     │
│  ┌──────────────── Backend ────────────────────────────────┐  │
│  │ decode/regread -> 1-entry opbuf -> EXU -> commit        │  │
│  │                                  │                      │  │
│  │                                  └── LSU req/rsp        │  │
│  └──────────────────────┬──────────────────────────────────┘  │
│                         │ redirect/flush                       │
│                         └───────────────────► Frontend         │
│                                                              │
│       IFU AXI4-Lite master       LSU AXI4-Lite master         │
│                  └──────── Arbiter ────────┘                  │
└──────────────────────────────┬───────────────────────────────┘
                               ▼ one external master
                  Xbar -> SRAM / UART / CLINT / DECERR
```

这是逻辑划分，不要求每个方框立即成为独立时钟级。只有含 storage、`valid/ready`、stall 或 flush 语义的边界才值得做成 elastic stage。

### 3.1 指令并发模型

- 每周期最多 issue 一条、commit 一条；任何时刻按程序顺序提交；
- IFU 可在 backend 执行或等待 LSU 时继续预取，最多填满 2-entry IFQ；
- backend 仅保留一条 executing instruction；年轻指令最多停在 opbuf/IFQ；
- load/store 未完成时不允许年轻指令进入 EXU，因此不需要 OITF、ROB 或 register scoreboard；
- ALU 指令允许同一周期“旧指令 commit + 新指令进入 EXU”，由 writeback-to-read bypass 解决边界相关；
- 初期 IFU 和 LSU 各最多一笔 outstanding；Arbiter 初期全局最多放行一笔，正确后再评估读通道并发。

这种结构已有真实的 fetch/execute overlap 和 backpressure，但状态空间仍可控。

## 4. 冻结的内部接口

接口名称可随 RTL 风格调整；以下 payload 和握手语义在实现前应先固定。可以使用平铺 Verilog ports 或 packed bus，不要求为了计划改写成 SystemVerilog `interface/struct`。

### 4.1 Frontend → Backend：instruction context

```text
if_valid / if_ready
if_pc / if_inst / if_fetch_err
if_pred_taken / if_pred_npc / if_pred_meta   // 第一版可置零
```

规则：

- `if_valid && !if_ready` 时所有 payload 保持；
- context 进入 backend 后，PC/inst 不再从 IFU 当前输出重新取值；
- redirect 只清除年轻 context，不得清除正在 commit 的指令；
- prediction metadata 从第一版就保留接口位置，静态不跳转时 `pred_npc = pc + 4`。

### 4.2 Backend → Frontend：redirect

```text
redirect_valid / redirect_target / redirect_reason
```

统一优先级：

```text
reset > synchronous exception/trap > mret > resolved branch/jump > predicted/sequential fetch
```

IFU 不假设已握手的 memory request 可取消。redirect 发生时：

1. 清空 IFQ 中的年轻指令；
2. 对已发出但未返回的 fetch 标记 `drop_rsp` 或旧 epoch；
3. 旧 response 返回后只消除 outstanding，不得进入 IFQ；
4. 从 redirect target 发起新请求。

单 outstanding 时一个 generation bit 或 `drop_rsp` 即可，不必一开始实现通用 tag 系统。

### 4.3 Backend ↔ LSU

```text
lsu_req_valid / lsu_req_ready
lsu_req_write / lsu_req_addr / lsu_req_size
lsu_req_wdata / lsu_req_wstrb / lsu_req_unsigned

lsu_rsp_valid / lsu_rsp_ready
lsu_rsp_rdata / lsu_rsp_resp
```

- AGU、byte lane、store strobe、load extension 属于 LSU；
- executing instruction 的 `{pc, inst, rd, control}` 保存在 backend，因此当前无需给 LSU 增加 instruction tag；
- request 接受后，LSU 必须锁存全部 payload；
- load 收到成功 response 后才可写 GPR；store 收到 `B` response 后才可 commit；
- MMIO transaction 也只握手一次，stall 不得重复产生副作用。

### 4.4 Commit boundary

commit 可以先是 `ysyx_core` 内的一组集中信号，不必急于单独建模块：

```text
commit_valid
commit_pc / commit_inst / commit_npc
commit_rd_wen / commit_rd_idx / commit_rd_data
commit_csr_wen / commit_trap / commit_mret
commit_mem_valid / commit_mem_write / commit_mem_addr
commit_exception / commit_cause
```

要求：

- committed PC、GPR、CSR 和 harness trace 只由同一个 commit event 更新/采样；IFU 内可独立维护 speculative fetch PC，但它不是 architectural state；
- 一条指令只产生一次 commit；
- stalled instruction 不得重复写寄存器、CSR 或 memory；
- branch/jump 的 redirect 可早于 commit 发出，但必须与同一 instruction context 对齐；
- exception 指令不执行正常 architectural writeback，年轻指令全部 flush。

store 是特殊情况：slave 可能在 CPU 收到 `B` response 前已经产生外部副作用。当前核不投机发射 store，且 store 始终是最老指令，因此仍具备精确顺序；CPU 在成功 `B` response 后才报告该 store commit，错误 response 则不得伴随有效 slave side effect。

### 4.5 Memory-side ownership

- IFU 只包含 AXI4-Lite `AR/R` adapter；
- LSU 包含 `AR/R/AW/W/B` adapter，`AW` 和 `W` 分别记录 handshake；
- Arbiter 从 request handshake 起保存 owner，直到对应 `R/B` response handshake；
- Xbar 同样保存目标 slave，不能在 response 时重新用地址组合译码；
- 未命中地址返回 `DECERR`，不允许 C++ `assert()` 越过 RTL 错误路径直接终止。

还必须满足 forward-progress 约束：IFU 只有在为返回数据预留了 IFQ/response-buffer credit 后才能发 request；LSU 同理预留 response slot。master 的 `RREADY/BREADY` 不得依赖另一笔尚未获准的 request，否则“Arbiter 锁住当前 owner、owner 又等待下一笔 transaction”会形成死锁。

## 5. 文件与模块落点

建议逐步形成以下结构，名称可以小幅调整，但责任不要重新混合：

```text
npc/vsrc/core/
  ysyx_core.sv              structural integration + architectural state
  ysyx_ifu.sv               PC/fetch ownership/redirect/stale response
  ysyx_fetch_queue.sv       2-entry elastic FIFO
  ysyx_opbuf.sv             1-entry issue context buffer
  ysyx_exu.sv               decode/execute/branch/CSR/commit control
  ysyx_lsu.sv               AGU/load-store transaction/result formatting
  ysyx_bpu_gshare.sv        optional phase, not initial dependency

npc/vsrc/bus/
  ysyx_ifu_axi4lite_adpt.sv
  ysyx_lsu_axi4lite_adpt.sv
  ysyx_axi_lite_arbiter.sv
  ysyx_axi_lite_xbar.sv

npc/vsrc/perip/
  ysyx_axi_lite_sram.sv
  ysyx_axi_lite_uart.sv
  ysyx_axi_lite_clint.sv
```

现有模块的处理原则：

- `ysyx_idu`、`ysyx_alu`、`ysyx_branch`、`ysyx_regfile`、`ysyx_csr` 先复用，不在结构重构时顺便重写；
- `ysyx_main_fsm` 在新 IFU/backend/LSU 全部接管状态后删除；
- `ysyx_d_ram_ctrl` 的地址、strobe 和 extension 逻辑迁入 LSU；
- `ysyx_i_ram`、`ysyx_d_ram` DPI 模块退出 core RTL，仿真 RAM 应位于 harness/model 边界；
- `npc/csrc/memory/ram_model.cpp` 扩展为独立 instruction/data port model，随后再增加 AXI slave model；
- `filelist.f` 每完成一个可编译小步再更新，不一次加入全部空模块。

## 6. 可执行实施阶段

每个 phase 必须满足“lint + 定向测试 + 最小系统回归”后才进入下一阶段。不要同时调试 core 生命周期、AXI 五通道和 SoC 地址图。

### Phase 0：冻结基线与量化手段

目标：得到可回退、可比较的结构重构起点。

1. [x] `filelist.f` 已展开进入 `$(VSRC)`，RTL 变更会触发重新构建。
2. [x] instruction RAM 已是持久化 transaction FSM，能保持 stalled response；当前 core 在 `IF_WAIT` 中始终 ready，response backpressure 的动态覆盖留到 Phase 2 directed test。
3. [x] 已运行并记录 lint、RV32E CPU tests、hello、RTC、yield-os、CSR DiffTest 和 10 个固定随机 seed，见 [`dev-log.md`](dev-log.md)。
4. [x] 已增加 cycle、commit、IF request stall、IF response wait/stall 和 redirect counters；尚无 data handshake/frontend buffer 的项目明确报告 `N/A`，分别在 Phase 1/2 接入。
5. [x] 已保存固定 `add` 程序的 commit trace 片段与完整 trace hash，见 [`phase0-add-commit-trace.txt`](phase0-add-commit-trace.txt)。

Gate：基线结果和 seed 可复现；当前工作独立提交。

### Phase 1：先建立 data transaction 边界

目标：core 不再直接调用 DPI data RAM，load/store 真正支持可变延迟。

> Checkpoint 1（2026-09-20）建立了 core 顶层 data-memory request/response channel 和独立 C++ data transaction FSM。Checkpoint 2 已进一步抽取 single-outstanding `ysyx_lsu`，backend 不再观察外部 memory handshake；当前接口名已统一为 `dmem_req/dmem_rsp`。Phase 1 至此完成，详见 [`dev-log.md`](dev-log.md)。

1. [x] 在 `ysyx_core` 顶层增加简单 `dmem_req/dmem_rsp` 端口；扩展 C++ RAM model 为独立 I/D transaction FSM。
2. [x] 实现 `ysyx_lsu`：接收 backend 已计算的 effective address，内部保存 direction/address/size/wdata，完成 request holding、load extension、response buffering 和 single-outstanding control。当前普通 ALU 继续兼任 AGU 加法器，AXI byte strobe 留给 Phase 4 adapter。
3. [x] backend 在 LSU response 前保持当前 instruction context；load/store 只在成功 response 后 commit。
4. [x] 删除 core 内 `ysyx_d_ram` 实例；DPI 只留在 harness/model 一侧。
5. [x] data request 覆盖随机 backpressure，memory response 覆盖随机 latency；standalone LSU test 另行覆盖 backend 暂不接收 result 时的 response-buffer holding。

最小 assertions：

- stalled request/response payload stable；
- outstanding 只能是 0 或 1；
- 没有 outstanding 时不能接受 response；
- 一次 request handshake 只产生一次 memory side effect；
- load/store 未完成时不得 commit。

Gate：所有 CPU tests 与 DiffTest 在 I/D 独立随机延迟下通过；MMIO 输出不重不漏。

完成状态（2026-09-20）：lint、LSU directed test、35/35 CPU tests、固定/压力 seed、hello UART、yield-os/CSR DiffTest 和 commit-trace 等价性均通过。由于 LSU 在仅有一笔 outstanding 且 response buffer 为空时始终接收 memory response，系统级 `dmem_rsp_valid && !dmem_rsp_ready` 预期为 0；真正被 backpressure 的是 LSU 到 backend 的 buffered result，这已由 directed test 覆盖。

### Phase 2：建立 elastic frontend/backend

目标：替换集中式 `IF_REQ -> IF_WAIT -> EXEC` 调度，形成真实前后端解耦。

#### Phase 2 命名约定

进入 Phase 2 前已统一稳定边界：active-low reset 使用 `rst_n`；harness 只观察 `commit_valid/commit_pc/commit_inst/commit_is_mmio`；core memory channel 使用 `imem_req/imem_rsp` 与 `dmem_req/dmem_rsp`；backend 与 LSU 使用 `lsu_req/lsu_rsp`。Phase 2 新增或迁移的信号遵循：

- IFU 到 backend 的 instruction context 使用 `if_ctx_valid/ready/pc/inst/error`，预测字段继续采用 `if_ctx_pred_*`；
- backend 到 IFU 的控制流恢复接口使用 `redirect_valid/target`，buffer 清除事件统一使用 `flush`；
- decoder 输出统一加 `dec_` 前缀，并将旧 `dm_re/dm_we_raw/dm_type` 拆为 `dec_is_load/dec_is_store/dec_mem_size/dec_mem_unsigned`；
- GPR 接口使用 `rs1_idx/rs2_idx/rd_idx`、`rs1_data/rs2_data` 和 `gpr_wen/wb_data`，避免用 `rd0/rd1` 表示 source operand；
- execution datapath 使用 `alu_lhs/alu_rhs/alu_result`、`branch_taken` 等语义名称；
- 有状态信号使用 `_q`，对应 next-state 使用 `_d`，handshake 事件使用 `_fire`；实例统一使用 `u_<role>`。

这些修改随相关 context/stage 落地完成，不单独对仍将删除的 `ysyx_main_fsm` 做美化重命名。

#### Phase 2A：IFU 与 IFQ

1. [x] 实现 `ysyx_ifu`，由它拥有 fetch PC、request outstanding、response 和 redirect discard 状态。
2. [x] 使用 `ysyx_gnrl_fifo` 加入 2-entry IFQ；backend stall 时 IFU 可继续预取至队列满，发 request 时必须预扣一个返回 credit。单 entry 的边界缓冲统一使用 `ysyx_gnrl_rv_reg`；两者均通过 `flush` 丢弃 redirect 前的年轻 context。
3. [x] 将 `if_ctx_{pc,inst,error,pred_*}` 作为完整 context 入队，并通过 `if_ctx_valid/if_ctx_ready` 交给 backend。
4. [x] directed test 覆盖：request stall、backend stall、queue full、redirect 时无 outstanding、redirect 时有 outstanding、旧 response 返回。

完成状态（2026-09-20）：`ysyx_ifu` 以 `REQ/WAIT/DROP` 管理单笔 fetch transaction；request 只在 IFQ 有 credit 时发出，故正常 response 到达时无需临时 backpressure。redirect 同步清空 IFQ；已经握手且不可取消的旧请求转入 `DROP`，其 response 仅解除 outstanding，不进入 IFQ。当前 prediction metadata 为 static not-taken，`error` 留待 Phase 3 接入。原 `ysyx_main_fsm` 已不再管理 instruction-memory handshake，但仍作为 `WAIT_CTX/EXEC/LSU_WAIT` 过渡 backend controller，待 Phase 2B 的 opbuf/EXU 落地后删除。

Phase 2A gate 已通过：IFU directed test、primitive/LSU tests、lint、35/35 CPU tests、10-seed 压力回归、hello、yield-os/CSR DiffTest 和完整 commit-trace 等价性均正常。固定 `add` 配置下 cycles 从 6639 降至 5121，CPI 从 6.063 降至 4.677；这证明 fetch 已能与 backend/LSU 等待重叠，但不作为后续结构决策的唯一性能依据。

#### Phase 2B：opbuf 与 backend

1. [x] 加入 1-entry opbuf，锁存 instruction context、`dec_*` 译码结果、`rs1_data/rs2_data` 和提交所需控制。
2. [x] EXU 只消费 opbuf，不再直接读取 IFU 当前组合输出。
3. [x] ALU/branch/CSR 指令完成后集中 commit；load/store 通过 LSU 等待。
4. [x] 允许旧 ALU 指令 commit 与新指令进入 EXU 同周期，加入 GPR writeback-to-read bypass。
5. [x] 分支、jump、trap、mret 统一产生 `redirect_valid/redirect_target`，并用 `flush` 清除 IFQ/opbuf 中的年轻 context。
6. [x] 删除 `ysyx_main_fsm`；`ysyx_core` 退化为模块连接和 architectural state 集成层。

核心 assertions：

- IFQ/opbuf 在 `valid && !ready` 时 payload stable；
- flush 后的 context 永远不能 commit；
- commit PC 严格按程序控制流前进；
- 每周期最多 issue/commit 一条；
- 除 reset 外，没有 commit 就不能更新 PC/GPR/CSR；
- stale fetch response 不能进入 IFQ。

Gate：随机 I/D stall 下回归通过；branch/trap/yield-os/CSR DiffTest 通过；与 Phase 0 commit trace 仅允许周期位置不同。

完成状态（2026-09-20）：decoder 和 GPR read 以 IFQ head 为输入，完整 decode/operand/commit context 进入基于 `ysyx_gnrl_rv_reg` 的 1-entry opbuf；`ysyx_exu` 统一完成 ALU、branch、CSR、redirect 和 commit，并以局部 `mem_wait_q` 持有 load/store 至 LSU result 返回。旧指令 commit 与新 context 入队可同周期发生，RAW 由 writeback-to-read bypass 处理。redirect 指令是 opbuf 中最老指令，本身在 commit 时出队；同周期 IFU 已抑制并 flush 年轻 context，因此无需清除正在 commit 的 opbuf entry。`ysyx_main_fsm` 已删除。

Phase 2B gate 已通过：EXU directed test、primitive/LSU/IFU tests、lint、35/35 CPU tests、10-seed 压力回归、hello、yield-os/CSR DiffTest 均正常；固定 `add` 配置下 commit trace 哈希仍为 `4a87442ab99f4b4d6e362ee8f38dd67c2299954785b211081f051fc03eb4af75`，cycles/CPI 与 Phase 2A 相同（5121/4.677）。

### Phase 3：精确错误语义与可观察性

目标：总线错误通过 architectural path 处理，不依赖 harness abort。

1. [x] 将 `imem_rsp_error` 作为 `if_ctx_error` 带入 instruction context，并让 `lsu_rsp_error` 随 LSU result 返回 backend。
2. [x] 实现 instruction/load/store access fault（`mcause=1/5/7`）；本阶段不引入 `mtval`，避免扩大尚无 workload 需求的 CSR/DiffTest ABI。
3. [x] exception 不执行正常 GPR/CSR/store writeback，redirect 到 `mtvec`，年轻 context flush；失败 store 在 C++ backend 校验通过前不产生副作用。
4. [x] commit trace v3 记录 exception/cause、redirect reason、memory address/response，以及相邻 commit 之间的 cycle 数和 stall bitmask；DiffTest 失败时的有限 ring trace 同步显示这些字段。

Gate：人为制造 fetch/load/store error 都能得到一次精确 trap 或受控 BAD TRAP，并可从 trace 定位首个错误 transaction。

完成状态（2026-09-25）：IFU/LSU response error 已贯通到统一 EXU commit；NEMU reference 的 `difftest_raise_intr()` 可在不执行 faulting instruction 的情况下构造相同 trap 后状态。`make -C npc access-fault-test` 分别注入非法取指、load 和 store，检查 `mcause=1/5/7`、`mepc`、GOOD TRAP、RAM error log 与 commit trace fault record，三项均通过。正常路径的 35/35 CPU tests、10-seed `add` 压力回归、hello、yield-os/CSR DiffTest 均正常；固定 `add` 的前五列 architectural trace 与 Phase 2B 完全一致。

> **后续规划说明（2026-09-28）**：本文件以 Phase 3 作为 `1-memory-request` 的完成边界。下面 Phase 4～7 是早期形成的后续设想，保留用于理解设计演进，但其任务拆分、优先级、目录归属和验收标准已由 [`../roadmap.md`](../roadmap.md) 重新规划，不再作为当前执行计划。当前工作从 [`../2-axi4-lite/plan.md`](../2-axi4-lite/plan.md) 开始，并按 roadmap 中与目录编号一致的 milestones 推进。

### Phase 4：AXI4-Lite IFU/LSU masters

目标：满足 B1 对两个 master 接口的要求，同时不改变 backend-facing 接口。

1. 先阅读并记录官方 AXI4-Lite 依赖规则；讲义只用于确定工程任务，不替代协议规范。
2. 实现 IFU `AR/R` adapter；分别随机化 `ARREADY`、`RVALID` 和 CPU `RREADY`。
3. 实现 LSU `AR/R/AW/W/B` adapter；`AW`/`W` 必须可在不同周期、任意先后完成。
4. 独立验证两个 master 后再接入 core；禁止用“slave 总是 ready”掩盖 holding-rule 错误。
5. 保持每个 master 单 outstanding，暂不加入 burst、ID 或乱序返回。
6. master 内保留 response buffer/credit，保证已接受的 transaction 最终总能消费 response，不把上游 stall 反向变成系统死锁。

Gate：IFU/LSU 单独协议测试与全程序回归通过；backend RTL 不引用任何 AXI channel 信号。

### Phase 5：Arbiter、Xbar 与最小 B1 system

目标：core 最终只暴露一个 AXI4-Lite master，并完成端到端总线验证。

1. 实现 IFU/LSU Arbiter：LSU 可优先以缩短 data stall，但必须避免 IFU 永久饥饿；owner 保持至 response handshake。
2. 正确处理 read 与 write channel；第一版允许全局只进行一笔 transaction，先保证归属清晰。
3. 实现 Xbar 和地址表；锁存目标 slave；未命中地址返回 `DECERR`。
4. 实现 AXI4-Lite SRAM、最小 UART TX 和只读 64-bit `mtime` CLINT。
5. directed test 覆盖 IFU/LSU 同时请求、AW/W 分离、各 slave backpressure、非法地址和公平性。

Gate：CPU tests、hello、RTC、yield-os、CSR DiffTest、RT-Thread workload 通过；Arbiter/Xbar/devices 各有 directed test，多 seed 随机 stall 通过。

### Phase 6：可选的 pre-SoC BPU 增量

目标：在不改变既有 stage/bus 边界的前提下验证一次有量化收益的微架构优化。

1. 先以 static not-taken 运行，记录 conditional branch、taken、redirect、mispredict 和 CPI。
2. 实现独立 `ysyx_bpu_gshare`：建议从 8-bit GHR + 128-entry 2-bit PHT 起步，参数可调。
3. IFU minidecode 计算 conditional branch/JAL immediate target；JALR 初版仍交由 EXU 解析。
4. instruction context 携带 prediction、PHT index 和 GHR snapshot；只在正确路径的 resolved branch 更新训练状态。
5. mispredict 时恢复/重建 speculative history，并复用既有 redirect/flush 网络。
6. 用相同 workload 比较 CPI、MPKI/accuracy 和面积/lint 结果，不以“加入了 predictor”代替收益证明。

此 phase 推荐在 SoC 前完成，但**不阻塞 B1/SoC 接口 sign-off**。前面已冻结 prediction metadata 和 redirect 接口，因此延期也不会导致结构返工。

### Phase 7：pre-SoC sign-off 与 B2 接入

1. 冻结 core 对外 AXI4-Lite、interrupt/time/reset/debug/commit 接口和地址无关的内部边界。
2. 输出 core block diagram、transaction timing、redirect/flush timing 和 commit/DiffTest verification diagram。
3. 按接入时最新 `ysyxSoC/spec/cpu-interface.md` 将单一 AXI4-Lite master 扩展为要求的完整 AXI4；不提前猜测 B2 位宽、ID 和地址图。
4. 保留 core 内 IFU/LSU/Arbiter；练习用 SRAM/UART 替换为 SoC slaves；CLINT 归属按届时规范决定。
5. 接入后只处理协议 adapter、地址图、reset/interrupt 和 DiffTest memory sync，不再大改 frontend/backend。

## 7. 验证矩阵

| 层次 | 重点 | 最低验收 |
| --- | --- | --- |
| Lint | 隐式 wire、组合环、位宽、锁存器 | `make lint TOP=<top>` 无新增 warning/error |
| Module directed | queue/opbuf/LSU/AXI/Arbiter/Xbar corner cases | 每个状态转换和错误 response 至少一个 case |
| Protocol assertions | stability、ownership、outstanding、flush | 随机测试全过程无 assertion failure |
| CPU + DiffTest | architectural state 和 commit 顺序 | 全部 RV32E CPU tests 通过 |
| AM workload | UART、RTC、trap/context | hello、RTC、yield-os 通过 |
| Long workload | 长时间 stall/redirect/MMIO 组合 | RT-Thread 仅作 workload，通过即可 |
| Performance | CPI 与 stall 归因 | 相同 binary/seed 可比较，数据能解释 |

随机失败必须打印 seed、首个错误 transaction 和最近一段 commit trace；固定复现 seed 纳入回归。波形只围绕首个 protocol/commit divergence 分析，不从最终 BAD TRAP 反向盲查。

推荐最小 assertion 集：

- `valid && !ready |=> valid && $stable(payload)`；
- response handshake 必须存在对应 outstanding/owner；
- outstanding counter 不溢出、不下溢；
- flush 后 context 不得到达 commit；
- `commit_valid` 每条动态指令最多一次；
- architectural register update 必须由 commit/trap event 许可；
- store request 不因 backpressure 重复接受；
- Arbiter/Xbar 在 transaction 完成前 owner/target 不变。
- 任一已接受 request 都已预留 response capacity，response ready 不循环依赖新 request。

## 8. 提交策略

不要把一次 phase 做成一个巨大提交。建议按以下可回退节点提交：

1. `refactor(npc): expose data request response port`
2. `refactor(npc): extract single-outstanding lsu`
3. `refactor(npc): extract ifu and add fetch queue`
4. `refactor(npc): add elastic op buffer and centralized commit`
5. `fix(npc): handle redirect and stale fetch response`
6. `feat(npc): add precise memory response errors`
7. `feat(npc): add ifu/lsu axi-lite adapters`
8. `feat(npc): add axi-lite arbiter and xbar`
9. `feat(npc): add b1 sram uart clint slaves`
10. `perf(npc): add gshare predictor`（可选）

每个提交至少可 lint；每个 phase 末尾必须功能回归。纯重命名/移动与行为变化尽量分开，便于 DiffTest 首次失配时二分。

## 9. 明确暂缓的内容

- 不实现 OITF、ROB、乱序执行、superscalar 或多发射；
- 不在当前阶段实现 cache、burst、多 AXI outstanding；
- 不为 M extension、AMO、PMP、NICE、CLIC 预先堆空接口；
- 不照搬参考核的 ICB/LBIU/address map/product wrapper；
- 不用固定五级流水的名字强行切割组合逻辑；
- 不让 software workload 扩展反客为主，RT-Thread 只承担验证压力。

这些功能将来只有在 workload、性能计数或 SoC 约束给出明确需求后再加入。

## 10. SoC 接入前的最终验收

以下各项同时满足，才视为 core microarchitecture 可以 sign-off：

- [ ] `ysyx_main_fsm` 已消失，IFU、backend、LSU 各自拥有局部状态；
- [ ] 2-entry IFQ 和 1-entry opbuf 在任意 backpressure 下正确工作；
- [ ] redirect 可清除年轻指令并丢弃 stale fetch response；
- [ ] load/store variable latency、MMIO 和 response error 不产生重复副作用；
- [ ] 所有 architectural state 与 harness trace 在统一 commit boundary 对齐；
- [ ] backend 不感知 AXI channel，IFU/LSU 分别通过 AXI4-Lite adapter；
- [ ] Arbiter/Xbar 对 request、response owner 和 DECERR 的处理有定向测试；
- [ ] SRAM/UART/CLINT 可完成 B1 端到端 workload；
- [ ] lint、protocol assertions、CPU tests、DiffTest、AM workload 和多 seed 回归通过；
- [ ] cycle/commit/CPI/stall/redirect counters 能解释结构变化；
- [ ] core/SoC、core/harness 接口有图和文字说明。

GShare 是否实现不作为 SoC 接入硬门槛；但 prediction metadata、redirect/flush 和 performance counter 必须已经预留，使它以后是局部优化而非再次重构。
