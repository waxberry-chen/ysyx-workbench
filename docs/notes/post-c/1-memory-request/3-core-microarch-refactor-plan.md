# B1 Core Microarchitecture Refactor Plan

本文规划在实现完整 AXI4-Lite 前，对当前集中式多周期 NPC 进行一次有限重构。目标是让 IFU、LSU 各自管理访存 transaction，backend 只管理指令执行和提交，从而避免总线细节继续膨胀进全局状态机。

讲义中的相关动机见 [`1.7.md`“总线视角下的处理器设计”](../../../misc/ysyx/docs/2306/basic/1.7.md#总线视角下的处理器设计)。讲义说明该重构并非强制要求，但分布式控制更利于接入 SoC 和后续流水线演进。

> 规划基线（2026-09-18）：最近提交为 `b272322f5fdc`（`feat(p-c-1): i ram handshake support v1`）。当前 RTL 使用 `IF_REQ -> IF_WAIT -> EXEC` 全局 FSM 控制取指和 commit，尚无明确 IFU/LSU transaction boundary。

## 1. 决策

采用“有限度的分布式控制”：

- 拆出 `ysyx_ifu`，局部管理 instruction request/response；
- 拆出 `ysyx_lsu`，局部管理 load/store request/response；
- 保留一个小型 backend controller，负责单条指令的执行、等待和精确提交；
- `ysyx_core` 逐步退化为结构连接和 architectural state 的集成层；
- 暂不把 IDU/EXU/WBU 全部改造成流水级，也不让 IFU 提前取多条指令。

“分布式”不等于取消所有状态机，而是每个模块只拥有自己的状态，模块间能否传递消息只取决于相邻接口的 `valid/ready`。backend 不应知道 AXI 的 `AR/R/AW/W/B` 握手状态。

## 2. 为什么现在需要重构

当前 FSM 只处理取指时尚且简单；若直接扩展 data access 和 AXI4-Lite，它将继续加入：

```text
IF_AR / IF_R
LOAD_AR / LOAD_R
STORE_AW / STORE_W / STORE_B
EXEC / COMMIT / ERROR
```

其中 `AW` 和 `W` 可以独立握手，还要记录 response、错误和来源。若这些状态全部进入全局 FSM，修改 memory latency、总线协议或 cache 都会影响 CPU 主控制，后续流水化也难以复用。

重构是否成功可用一条规则判断：

> 改变 IFU/LSU 外侧的总线延迟或协议时，不应修改 backend 的指令执行与 commit 控制。

## 3. 目标结构

```text
                         ysyx_core
┌─────────────────────────────────────────────────────┐
│ Backend / Execute & Retire                          │
│ PC、inst、IDU、ALU、GPR、CSR、next-PC、commit       │
│       │ fetch req/rsp           │ memory req/rsp    │
│       ▼                         ▼                   │
│  ┌───────────┐             ┌───────────┐            │
│  │ ysyx_ifu  │             │ ysyx_lsu  │            │
│  │ local FSM │             │ local FSM │            │
│  │   AR/R    │             │AR/R/AW/W/B│            │
│  └─────┬─────┘             └─────┬─────┘            │
└────────┼─────────────────────────┼───────────────────┘
         │ AXI4-Lite master        │ AXI4-Lite master
         └───────────┬─────────────┘
                     ▼
                  Arbiter -> Xbar -> SRAM/UART/CLINT
```

当前阶段 architectural PC 继续由 backend 持有。IFU 接收明确的 fetch PC，并在 response 中返回对应 PC；等实现流水线或分支预测后，再考虑由 frontend 持有 speculative fetch PC，并增加 redirect/flush 接口。

## 4. 模块职责与接口

### 4.1 IFU

IFU 负责一笔取指 transaction 的完整生命周期，不负责译码、next-PC 或 commit。

内部状态建议为：

```text
IDLE -> SEND_AR -> WAIT_R -> RESP -> IDLE
```

在升级 AXI4-Lite 之前，`SEND_AR/WAIT_R` 可先映射到当前简单 memory request/response。建议的 backend-facing interface：

```text
fetch_req_valid / fetch_req_ready / fetch_req_pc
fetch_rsp_valid / fetch_rsp_ready / fetch_rsp_pc
fetch_rsp_inst  / fetch_rsp_resp
```

IFU 必须：

- 最多维护一笔 outstanding request；
- request stall 时保持 `valid` 和 PC；
- response stall 时保持 `valid`、PC、instruction 和 response code；
- 只在 handshake 时改变 transaction ownership；
- 不直接更新 architectural PC 或产生 commit。

### 4.2 LSU

LSU 接收 backend 已计算完成的访存语义，负责地址、数据、掩码与总线 transaction。建议的 backend-facing interface：

```text
mem_req_valid / mem_req_ready
mem_req_write / mem_req_addr / mem_req_size
mem_req_wdata / mem_req_wstrb

mem_rsp_valid / mem_rsp_ready
mem_rsp_rdata / mem_rsp_resp
```

内部控制至少覆盖：

```text
load : IDLE -> SEND_AR -> WAIT_R -> RESP
store: IDLE -> SEND_AW_W -> WAIT_B -> RESP
```

`AW` 和 `W` 必须独立保持并分别记录 handshake；只有二者均被接受后才能等待 `B` response。LSU 负责 load 数据对齐/符号扩展及 store byte lane/WSTRB 生成，但不直接写 GPR、PC 或 CSR。

### 4.3 Backend

Backend 保留现有 IDU、ALU、branch、GPR、CSR 和 next-PC 数据通路，只通过抽象 transaction 接口访问 IFU/LSU。第一版仍保持单 issue、单条在途指令，可用小型生命周期控制：

```text
WAIT_FETCH -> EXECUTE -> WAIT_MEMORY -> COMMIT
```

也可以逐步用 `inst_valid`、`mem_pending` 等局部 valid state 代替枚举状态；两种写法均可，前提是 backend 不直接观察原始 AXI handshake。

### 4.4 Top-level、Arbiter 与 Xbar

- `ysyx_core` 只连接 backend、IFU、LSU 和 architectural state；
- Arbiter 记录当前 transaction 来自 IFU 还是 LSU，直到相应 response 完成；
- Xbar 只负责地址译码、请求/响应路由和 `DECERR`；
- SRAM/UART/CLINT 是 slave，不参与 CPU instruction lifecycle；
- 随机延迟属于 verification environment，不进入 CPU 功能 RTL。

## 5. Commit 语义

重构期间必须保持 commit-driven DiffTest 的定义不变：`commit_wb` 表示一条指令的 architectural effects 在该边沿一次性生效。

| 指令类型 | Commit 条件 |
| --- | --- |
| ALU、branch/jump、CSR | backend 执行完成 |
| `ecall/mret` | trap/return architectural state 更新时 |
| load | 收到成功的 `R` response，并准备写回 GPR |
| store | 收到成功的 `B` response |
| bus error | 不正常 commit；后续转换为对应 Access Fault，第一版至少应可观察地终止 |

所有 GPR/CSR/PC/store/trap/mret enable 仍必须由最终 commit/transaction event 门控，不能使用 decoder raw intent 直接产生副作用。

## 6. 分步迁移

### Step 0：冻结基线

- 保留当前 CPU tests、hello、RTC、yield-os 和 DiffTest 结果；
- 记录固定随机 seed、周期数和一份正常 commit trace；
- 不在同一提交中同时引入 AXI4-Lite、Arbiter 和模块重构。

### Step 1：只提取 IFU

- 将 `IF_REQ/IF_WAIT`、instruction register 和 request payload holding 移入 `ysyx_ifu`；
- 继续使用当前简单 instruction request/response 顶层端口；
- response 携带 `{pc, inst, resp}`，backend 只在 response handshake 后执行；
- 功能、指令周期数和 DiffTest 行为不应发生非预期变化。

### Step 2：收缩全局控制

- 将 `ysyx_main_fsm` 改成只管理 instruction lifecycle 的 backend controller，或用 valid state 取代；
- 删除其中对 memory bus phase 的直接控制；
- normal instruction、branch、CSR、trap/mret 先通过完整回归。

### Step 3：提取 LSU

- 用统一 `mem_req/mem_rsp` 包装现有 `d_ram_ctrl` 和 data-memory access；
- load 等待 response 后再写 GPR，store 等待 response 后再 commit；
- 确保 MMIO read/write 每笔 transaction 只调用一次 backend，不因 stall 重复产生副作用。

### Step 4：验证局部 backpressure

- 分别对 fetch request/response、memory request/response 注入 stall；
- 加入 request/response stability assertion；
- 使用固定延迟、随机延迟和多个可复现 seed 回归；
- 确认 `si 1` 仍严格执行一条 committed instruction。

### Step 5：升级 AXI4-Lite

- 先将 IFU 外侧替换为 AXI4-Lite read master；
- 再将 LSU 外侧替换为 AXI4-Lite read/write master；
- backend-facing interface 和 commit 逻辑保持不变；
- 两者独立通过 directed test 后再接 Arbiter、Xbar 和 devices。

## 7. 暂不实施

- 不让 IFU run ahead，不增加 fetch queue 或多 outstanding；
- 不提前实现 speculative PC、branch prediction、flush network；
- 不为纯组合的 IDU/EXU/WBU 强行添加装饰性的 `valid/ready`；
- 不在本次重构中加入 cache、流水线、复杂仲裁或通用参数化 interconnect；
- 不以模块数量衡量“分布式程度”，只有具备 payload ownership、holding rule 和局部状态的边界才是真正解耦。

## 8. 验收条件

- IFU/LSU 各自拥有并封装全部 memory transaction 状态；
- backend 不引用 `AR/R/AW/W/B` 信号或 memory latency；
- `ysyx_core` 顶层主要承担模块连接，不再集中生成所有握手；
- stall 期间 `valid` 和 payload 稳定，response 不丢失、不重复；
- 每条指令只产生一次 architectural side effect 和一次 commit；
- CPU tests、hello、RTC、yield-os 及 CSR DiffTest 全部通过；
- 改变 fixed/random latency 无需修改 backend RTL；
- lint 和最小 protocol assertions 通过。

完成该重构后，B2 可在 IFU/LSU 外侧扩展完整 AXI4；后续流水线阶段再将 backend 拆成有实际 storage、stall 和 flush 语义的 stages，而无需推翻 memory transaction boundary。
