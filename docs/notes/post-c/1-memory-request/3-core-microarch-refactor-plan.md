# B1 Core Microarchitecture Refactor Plan

本文固化从当前集中式多周期 NPC 到 B1 AXI4-Lite 系统的实施顺序。目标是让 IFU、LSU 各自管理 memory transaction，backend 只管理指令执行与精确提交，避免总线细节继续膨胀进全局状态机。

讲义动机见 [`1.7.md`“总线视角下的处理器设计”](../../../misc/ysyx/docs/2306/basic/1.7.md#总线视角下的处理器设计)。

> 定稿基线（2026-09-20）：最近提交为 `4d0aaf3`（`doc(p-c-1): add some plan docs`）；working tree 还包含已验证但未提交的持久化 RAM transaction model、request backpressure 和 RTL 接口收紧。`make lint` 通过，RV32E NPC CPU tests 35/35 通过。

## 0. 结论与启动门槛

当前功能基线足以开始重构，无需重做 C 阶段。但在大量修改 RTL 前有两个必须先处理的工程阻塞：

1. 将当前 RAM model、backpressure、RTL 门控与文档形成可回退的 baseline commit，不与 IFU/LSU 重构混在同一批 diff 中。
2. 修正 `npc/Makefile` 中 Verilator 目标的 RTL 依赖。当前 `$(VSRC)` 未由 `filelist.f` 展开，修改 `.sv` 后可能错误显示 up to date；重构期间不应依赖人工记忆每次执行 `make clean`。

Phase 0 同时应增加 total-cycle 计数，记录 cycles、committed instructions、CPI、主要 stall 和固定 seed commit trace。这不阻止结构重构，但在声称“微架构优化”前必须具备，否则只能证明功能等价，无法量化收益。

以下内容不阻止现在开始，但是后续 phase gate：

- IFU/LSU 接口落地时加入少量 protocol assertion；
- 进入 AXI4-Lite 实现前阅读官方 AMBA AXI 规范；当前 `docs/` 未发现本地 AXI 官方规范，讲义不能代替对握手依赖规则的 RTFM。
- B2 开始前以当时的 `ysyxSoC/spec/cpu-interface.md`、地址图和数据位宽为准，不在 B1 提前固化可能变动的 SoC 细节。

## 1. 架构决策与范围

采用“有限度的分布式控制”：

- 拆出 `ysyx_ifu`，局部管理 instruction request/response；
- 拆出 `ysyx_lsu`，局部管理 load/store request/response；
- 保留小型 backend controller，负责单条指令的执行、等待和精确提交；
- `ysyx_core` 逐步退化为结构连接与 architectural state 集成层；
- 暂不把 IDU/EXU/WBU 强行拆成流水级，也不增加多 outstanding、fetch queue、分支预测或 speculative PC。

第一版是 transaction ownership 和控制责任的结构解耦，不是 frontend run-ahead。Backend 仍等待当前指令 commit 后才请求下一条指令，因此没有指令间重叠和 IPC 收益。本轮收益是模块边界、可变延迟正确性和后续可扩展性。

重构成功的判据是：

> 改变 IFU/LSU 外侧总线协议或 memory latency 时，不需修改 backend 的指令语义与 commit 控制。

## 2. 目标结构

```text
                         ysyx_core
┌─────────────────────────────────────────────────┐
│ Backend: PC/IDU/EXU/GPR/CSR/commit             │
│       │ fetch req/rsp       │ memory req/rsp   │
│       ▼                     ▼                  │
│  ┌───────────┐         ┌───────────┐           │
│  │ ysyx_ifu  │         │ ysyx_lsu  │           │
│  │ local FSM │         │ local FSM │           │
│  └─────┬─────┘         └─────┬─────┘           │
│        │ AXI4-Lite M        │ AXI4-Lite M       │
│        └───────────┬───────────┘                 │
│                      ▼ Arbiter                  │
└────────────────────────┬────────────────────────┘
                         ▼ one external master
        B1 system: Xbar -> SRAM / UART / CLINT
        B2 system: ysyxSoC devices; CLINT retained by NPC
```

图中 AXI4-Lite 是 B1 最终边界。重构初期 IFU/LSU memory-facing 侧先使用简单 request/response，确认模块责任后再替换为 AXI4-Lite。B2 时 Arbiter 留在 NPC 内；练习用 SRAM/UART 由 ysyxSoC 设备替换，CLINT 按 SoC 约定保留在 NPC 侧。

## 3. 模块责任与接口

### 3.1 IFU

Backend-facing interface：

```text
fetch_req_valid / fetch_req_ready / fetch_req_pc
fetch_rsp_valid / fetch_rsp_ready / fetch_rsp_pc
fetch_rsp_inst  / fetch_rsp_resp
```

IFU 负责一笔取指 transaction 的完整生命周期，不负责译码、next-PC 或 commit：

- 最多一笔 outstanding request；
- request/response stall 时保持 `valid` 和全部 payload；
- request handshake 后 IFU 拥有 PC，response 返回同一 PC；
- backend 只在 response handshake 后拥有 `{pc, inst, resp}`；
- 简单 RAM 也保留 response code，当前固定为 `OKAY`。

初版局部状态可为 `IDLE -> SEND_REQ -> WAIT_RSP -> RESP`。转换为 AXI4-Lite 后，memory-facing 侧对应 `AR/R`。

### 3.2 LSU

Backend-facing interface：

```text
mem_req_valid / mem_req_ready
mem_req_write / mem_req_addr / mem_req_size
mem_req_wdata / mem_req_wstrb

mem_rsp_valid / mem_rsp_ready
mem_rsp_rdata / mem_rsp_resp
```

LSU 负责地址、byte lane、数据、符号扩展和 transaction，不直接更新 GPR/PC/CSR：

- load 等待 response 后才向 backend 返回处理后的数据；
- store 在收到成功 response 后才允许 commit；
- 等待期间锁存地址、数据、size、strobe 和 MMIO 属性；
- MMIO/backend 每笔 transaction 只访问一次，不因 stall 重复产生副作用；
- AXI4-Lite store 的 `AW` 和 `W` 独立保持并分别记录 handshake，两者均完成后才等待 `B`。

### 3.3 Backend

Backend 保留现有 IDU、ALU、branch、GPR、CSR 和 next-PC，只通过上述抽象接口访问 IFU/LSU。初版仍为 single-issue/single-instruction-in-flight，生命周期可概括为：

```text
WAIT_FETCH -> EXECUTE -> WAIT_MEMORY(if needed) -> COMMIT
```

Backend 在等待期间必须保存与提交对齐的 PC、instruction、译码结果或足够的 memory context、MMIO 标记和 exception response，不能在返回后重新使用已改变的 raw intent。

### 3.4 Arbiter、Xbar 与 devices

- Arbiter 记录 transaction 来自 IFU 还是 LSU，保持 owner 到对应 `R/B` response handshake，不在 response 前重新仲裁；
- Xbar 记录 slave 归属，只负责地址译码、请求/响应路由和未命中地址的 `DECERR`；
- B1 需要 AXI4-Lite SRAM slave 和最小 UART TX slave，否则无法端到端验证读写五通道与 Xbar；
- CLINT 至少提供 64-bit `mtime`，后续按 ysyxSoC 要求保留在 NPC 中；
- 随机延迟是 verification behavior，不进入 CPU 功能 RTL。

## 4. Commit 与错误语义

`commit_wb` 仍表示一条指令的 architectural effects 在该边沿一次性生效：

| 指令类型 | Commit 条件 |
| --- | --- |
| ALU、branch/jump、CSR | backend 执行完成 |
| `ecall/mret` | trap/return architectural state 更新 |
| load | 收到成功 response，已准备写回 GPR |
| store | 收到成功 write response |
| bus error | 不正常 commit；B1 初版至少带上 PC/地址/response 可观察地终止，B2 前决定是否转换为 Access Fault |

PC、GPR、CSR、store、trap/mret 的最终 enable 必须由 commit/transaction event 门控。`commit_pc`/`commit_inst`/`commit_is_mmio` 也必须来自同一笔被锁存的 instruction context，以保持 Itrace 和 DiffTest 对齐。

## 5. 最终实施顺序

| 总体顺序 | 实施 phase |
| --- | --- |
| 1. 确定 NPC 重构 plan | 本文定稿 + Phase 0 |
| 2. 初步前后端解耦多周期版 | Phase 1：IFU、backend、LSU 与协议验证 |
| 3. AXI4-Lite fetch/load/store | Phase 2 |
| 4. Arbiter、Xbar、CLINT | Phase 3，同时补齐 SRAM slave 和 UART |
| 5. B2 接入 SoC | Phase 4 |

### Phase 0：冻结基线

1. 修正 RTL build dependency，用一次 `.sv` touch 验证会触发重建。
2. 完成当前 working tree 的 lint、CPU tests、hello、RTC、yield-os、CSR DiffTest 与压力 seed 回归。
3. 增加并记录 cycles/instructions/CPI/stall 基线。
4. 提交当前变更，后续每个 phase 使用独立小提交。

### Phase 1：内部解耦的多周期 core

1. 只提取 IFU：移入 fetch request/wait、PC ownership 和 response register，继续使用当前简单 memory port。
2. 收缩 `ysyx_main_fsm`：backend 不再观察 memory-side handshake，只通过 fetch/memory message 接口工作。
3. 提取 LSU：将现有 `d_ram_ctrl`/DPI access 包装为单 outstanding `mem_req/mem_rsp`，load/store 等待 response 后提交。
4. 分别向 fetch 和 data request/response 注入 fixed/random stall，加入 payload stability、单 outstanding 和 no-side-effect-without-commit assertions。

Phase 1 不改 AXI，便于将“CPU 生命周期错误”和“AXI 协议错误”分开定位。

### Phase 2：AXI4-Lite IFU/LSU

1. 根据官方规范冻结五通道 payload、holding rule、依赖方向和 response 语义。
2. 先将 IFU memory-facing 侧替换为 AXI4-Lite `AR/R` master，用独立 SRAM slave 验证。
3. 再将 LSU 替换为 `AR/R/AW/W/B` master，必须覆盖 `AW` 与 `W` 不同周期握手。
4. 各 master 独立通过 directed test、随机 valid/ready 和系统程序后再合并。Backend-facing interface 和 commit 逻辑不变。

### Phase 3：B1 最小总线系统

1. 实现 IFU/LSU 二选一 Arbiter，保持 owner 到 response handshake。
2. 实现最小 Xbar，按地址路由 SRAM/UART/CLINT，未命中返回 `DECERR`。
3. 实现 AXI4-Lite SRAM slave、UART TX 寄存器和只读 64-bit `mtime` CLINT。
4. 使用 directed bus tests、assertion、多 seed 随机延迟、CPU tests、hello、RTC、DiffTest 和 RT-Thread 验证。RT-Thread 只作为长时间 workload，不扩展系统软件工作。

### Phase 4：B2 接入准备

1. 将 NPC 单一对外 AXI4-Lite master 按当前 ysyxSoC 规范扩展为完整 AXI4。
2. 保留 NPC 内 IFU/LSU Arbiter 和 CLINT，移除练习用 SRAM/UART。
3. 接入 ysyxSoC 后再处理 MROM、新地址图、DiffTest memory 同步和 AM 平台差异。

## 6. 验证策略

每个 phase 都按以下层次验收，不等到 RT-Thread 失败后才看总线波形：

1. module-directed：单独构造 request/response、长 stall、AW/W 乱序握手、DECERR；
2. assertion：检查 stall 期间 payload 保持、单 outstanding、response 归属和 commit 副作用；
3. CPU tests + DiffTest：检查 architectural state；
4. hello/RTC/yield-os：检查 MMIO 和 trap path；
5. RT-Thread：长时间压力测试；
6. waveform：只对首个失败 transaction/commit 做周期级定位。

`si 1` 始终应精确执行一条 committed instruction；随机测试必须打印 seed、transaction/stall 计数，失败 seed 作为固定回归保留。

## 7. 暂不实施

- 不让 IFU run ahead，不增加 fetch queue 或多 outstanding；
- 不实现 speculative PC、branch prediction 或 flush network；
- 不为纯组合 IDU/EXU/WBU 强行添加装饰性 `valid/ready`；
- 不引入 cache、复杂仲裁、通用参数化 NoC/interconnect；
- 不以模块数量衡量分布式程度；只有具备 payload ownership、holding rule 和局部状态的边界才是有效解耦。

## 8. B1 验收条件

- IFU/LSU 各自封装全部 memory transaction 状态；
- backend 不引用 AXI `AR/R/AW/W/B` 或 memory latency；
- Arbiter/Xbar 锁定 response 归属，stall 期间 `valid/payload` 稳定；
- 每条指令只产生一次 architectural side effect 和一次 commit；
- 改变 fixed/random latency 不需修改 backend RTL；
- CPU tests、hello、RTC、yield-os、CSR DiffTest 和 RT-Thread 通过；
- Arbiter/Xbar/SRAM/UART/CLINT 各有 directed test，未命中地址产生可观察 `DECERR`；
- lint 和最小 protocol assertions 通过；
- 能输出 cycles、instructions、CPI 和主要 stall 计数，改造前后差异可解释。

完成后，B2 只需在 NPC 单一对外 master 边界扩展完整 AXI4；后续流水线再将 backend 拆成有真实 storage、stall 和 flush 语义的 stages，不需推翻 memory transaction boundary。
