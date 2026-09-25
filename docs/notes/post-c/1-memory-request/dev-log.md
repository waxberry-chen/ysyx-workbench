# Variable-latency Memory Refactor Development Log

## 2026-09-20：Phase 0 baseline

### 1. 结论

Phase 0 的可观测性、可复现随机回归和基线 trace 已建立，当前结果足以开始 Phase 1 data transaction refactor。

本轮没有改变 CPU architectural behavior。需要延后到后续结构阶段的指标均明确显示为 `N/A`，不使用恒为零的数值伪装成已有覆盖：

- data RAM 仍是 core 内部的零延迟 DPI access，尚无 data request/response stall；
- 当前 frontend 没有预取队列，只有 redirect，没有 flush；
- RAM model 可以保持 response，但当前 `IF_WAIT` 始终令 `if_rsp_ready=1`，所以动态回归未产生 response backpressure。

### 2. 实现内容

#### 2.1 Simulation statistics

新增 `npc/csrc/utils/sim_stats.cpp` 与对应 header，在每个 reset 之后的 active cycle 采样：

- total cycles、committed instructions 和 CPI；
- IF request stall：`if_req_valid && !if_req_ready`；
- IF response wait：`if_rsp_ready && !if_rsp_valid`；
- IF response stall：`if_rsp_valid && !if_rsp_ready`；
- redirect：一条 commit 后的 NPC 不等于 `PC + 4`。

统计从 reset 解除后开始，到 ebreak 被 harness 识别前结束。当前 harness 不执行 ebreak 本身，因此 RAM transaction 数通常比 committed instruction 多 1：最后一笔 transaction 取回了 ebreak，但 ebreak 不进入 DiffTest/commit 计数。

#### 2.2 Commit trace

新增命令行选项：

```text
--commit-trace=FILE
```

每条记录包含：

```text
nr pc inst npc architectural_state_hash
```

hash 使用 post-commit PC、32 个 GPR 和四个 CSR 计算，用于快速确认两轮运行不仅控制流相同，architectural state 也相同。固定 `add` case 的前 64 条记录保存在 [`phase0-add-commit-trace.txt`](phase0-add-commit-trace.txt)。

完整 trace 共 1095 条 commit，两次相同配置运行通过 `cmp`，SHA-256 均为：

```text
4a87442ab99f4b4d6e362ee8f38dd67c2299954785b211081f051fc03eb4af75
```

复现命令：

```bash
npc/build/Vysyx_core \
  -d nemu/build/riscv32-nemu-interpreter-so -b \
  --ram-seed=42 --ram-max-latency=3 --ram-ready-percent=75 \
  --commit-trace=/tmp/npc-phase0-add.trace \
  am-kernels/tests/cpu-tests/build/add-riscv32e-npc.bin
```

#### 2.3 Fixed-seed regression

`npc/Makefile` 新增 `seed-regress`，默认使用 seeds 1～10、最大 latency 7、request-ready 50%，每个 seed 的日志写入 `npc/build/seed-logs/`。target 同时检查进程退出状态和 `HIT GOOD TRAP`，避免 BAD TRAP 被误记为通过。

同时把 `npc/csrc/**/*.h` 加入 Verilator binary 的 prerequisites；以后只修改 harness header 也会触发重新构建，不需要手动 `make clean`。

用法：

```bash
make -C npc seed-regress \
  IMG=/absolute/path/to/test.bin \
  ARGS='-d /absolute/path/to/riscv32-nemu-interpreter-so'
```

还修正了 NPC main 的退出状态：`SIM_ABORT` 或 `SIM_END && halt_ret != 0` 返回非零，便于自动回归可靠判定失败。

### 3. Baseline measurement

确定性 workload：`cpu-tests/add`，RAM seed 42、最大 latency 3、request-ready 75%。

| Metric | Result |
| --- | ---: |
| committed instructions | 1095 |
| cycles | 5319 |
| CPI | 4.858 |
| IF request stall cycles | 390 |
| IF response wait cycles | 1642 |
| IF response stall cycles | 0 |
| redirects | 212 |
| fetch requests/responses | 1096 / 1096 |

这组 CPI 只代表当前三态串行 core 在指定 memory timing 下的 simulation baseline。后续对比必须使用相同 binary、RAM 参数和 commit 口径。

10-seed stress 使用相同 `add` image、最大 latency 7、request-ready 50%：

- seeds 1～10 全部 `HIT GOOD TRAP`，DiffTest 无失配；
- commit 数均为 1095；
- cycles 范围 8146～8351；
- CPI 范围 7.439～7.626；
- stall 数随 seed 改变，证明 timing schedule 确实不同。

### 4. Verification record

| Item | Command/configuration | Result |
| --- | --- | --- |
| RTL lint | `make -C npc lint` | 通过；仅有既存 unused parameter/signal warnings |
| RV32E CPU tests | `make ARCH=riscv32e-npc run` | 35/35 PASS，DiffTest ON |
| hello/UART | `kernels/hello`, `mainargs=I-love-ysyx` | 输出参数并 HIT GOOD TRAP |
| RTC | `am-tests`, `mainargs=t` | 连续观察 29 s，日期及秒计数正确；case 本身不退出 |
| interrupt/yield | `timeout 10s ... mainargs=i` | 进入测试并持续输出 `y`；timeout 124 为主动终止 |
| yield-os | `timeout 8s make ARCH=riscv32e-npc run` | 持续交替输出 `AB`；timeout 124 为主动终止 |
| CSR DiffTest | interrupt/yield 与 yield-os 运行期间启用 NEMU REF | 未发现 PC/GPR/CSR mismatch |
| fixed seeds | `make -C npc seed-regress ...` | seeds 1～10 全部通过 |
| trace determinism | 相同 seed/config 连续运行两次后 `cmp` | 完全一致 |

受 sandbox 权限影响，本次构建临时将 `CCACHE_DIR`/`CCACHE_TEMPDIR` 指向 `/tmp`；这只是验证环境设置，不是工程依赖。

### 5. Phase 1 handoff

Phase 1 开始后沿用现有统计口径，并补齐：

1. data request stall、data response wait/stall；
2. load/store transaction count 和 MMIO count；
3. data outstanding 0/1 assertion；
4. 相同 `add` trace 的 architectural state 对比；
5. 对 `load-store`、hello 和 RTC 执行多 seed I/D 独立延迟回归。

Phase 2 引入 IFQ/opbuf 后再把 frontend flush 变成实际 counter，并以 directed test 验证 fetch credit：已接受 request 的 response 必须始终有预留空间；真正的动态 backpressure 发生在 IFQ 到 backend 的 context 边界。

## 2026-09-20：Phase 1 checkpoint 1——data transaction boundary

### 1. 提交边界

本 checkpoint 只完成建议提交 `refactor(npc): expose data request response port`，不继续混入 `ysyx_lsu` 模块抽取。

完成后的结构是：

```text
ysyx_core
  current decode/ALU/d_ram_ctrl
  current main FSM + D_REQ/D_WAIT/D_COMMIT
          |
          | d_req/d_rsp
          v
C++ DataRamModel -> paddr_read/paddr_write -> PMEM/MMIO
```

core 已不再实例化或编译 DPI-based `ysyx_d_ram`；被接受的 data request 由 C++ model 锁存，经过独立随机 latency 后只调用一次 `paddr_read()` 或 `paddr_write()`。这使 memory/MMIO side effect 不会因 request/response stall 重放。

### 2. 接口与时序

顶层新增：

```text
d_req_valid / d_req_ready
d_req_write / d_req_addr / d_req_size / d_req_wdata
d_rsp_valid / d_rsp_ready / d_rsp_data
```

`d_req_size` 使用 `log2(bytes)` 编码：0/1/2 分别表示 1/2/4-byte access。当前简单 transaction 支持课程已有的 unaligned access；转换 AXI4-Lite 时再由 LSU/adapter 生成 byte lane 和 strobe，必要时处理跨 beat 访问。

FSM 暂时扩展为：

```text
IF_REQ -> IF_WAIT -> EXEC
                       | non-memory: commit
                       v memory
                     D_REQ -> D_WAIT -> D_COMMIT -> IF_REQ
```

- `D_REQ` 在 request stall 时保持 instruction、address、size 和 write data；
- `D_WAIT` 不更新 PC/GPR/CSR，也不重新发 request；
- response handshake 时锁存 load data；
- `D_COMMIT` 在下一有效边沿完成 load writeback/store commit 和 PC 更新。

增加 `D_COMMIT` 而不是让 response handshake 直接 commit，是为了保持当前 harness 的既有约定：`cpu_exec()` 在 active edge 前读取已经稳定的 `commit_wb/pc/inst`。它增加一个周期，但此 checkpoint 优先保证时序含义明确；后续重构 harness sampling 或 LSU response buffer 时可重新评估。

### 3. C++ model 与检查

I/D port 各有独立 FSM 和 PRNG stream：

```text
IDLE --req_fire--> WAIT --latency_done--> RESP --rsp_fire--> IDLE
```

data seed 由 command-line RAM seed 异或固定常量得到，因此配置可复现，同时 I/D timing schedule 不共用 RNG 状态。

DataRamModel 当前检查：

- request stall 后下一周期 `valid/write/addr/size/wdata` 必须保持；
- request size 只能是 1/2/4 bytes；
- 非 IDLE 状态不能接受第二笔 request；
- response 数不得超过 accepted request 数；
- memory backend 每笔 request 最多调用一次。

simulation statistics 已新增 data request stall、response wait/stall；model report 另行给出 load/store/request/response 数量。

### 4. 等价性与性能基线

确定性 `cpu-tests/add`，seed 42、最大 latency 3、I/D request-ready 75%：

| Metric | Phase 0 | Checkpoint 1 |
| --- | ---: | ---: |
| committed instructions | 1095 | 1095 |
| cycles | 5319 | 6639 |
| CPI | 4.858 | 6.063 |
| data transactions | N/A | 282 |
| data loads/stores | N/A | 243 / 39 |
| data request stall cycles | N/A | 117 |
| data response wait cycles | N/A | 395 |

CPI 上升是预期结果：原 data RAM 为零延迟组合读/沿上写，现在每条 load/store 都经过 `D_REQ/D_WAIT/D_COMMIT`，并叠加随机 request stall/response latency。当前目标是建立正确 transaction boundary，而不是在仍为集中式串行 core 时优化性能。

Phase 0 和 checkpoint 1 的完整 `add` commit trace 逐字节相同，SHA-256 均为：

```text
4a87442ab99f4b4d6e362ee8f38dd67c2299954785b211081f051fc03eb4af75
```

这说明 cycle timing 已改变，但 1095 个 commit 后的 PC、instruction 和 architectural-state hash 未改变。

### 5. 验证记录

| Item | Configuration | Result |
| --- | --- | --- |
| RTL lint | `make -C npc lint` | 通过，仅剩既存 unused warnings |
| RV32E CPU tests | 默认 seed 42/max-latency 3/ready 75% | 35/35 PASS，DiffTest ON |
| fixed-seed add | seeds 1～10/max-latency 7/ready 50% | 全部 GOOD TRAP；每次 282 requests = 282 responses |
| unaligned stress | seeds 1～3/max-latency 10/ready 30% | 全部 GOOD TRAP |
| hello/UART | `mainargs=I-love-ysyx` | 字符不重不漏，GOOD TRAP |
| RTC | 7 s timeout window | 连续输出 1～6 seconds；主动 timeout 124 |
| yield-os/CSR DiffTest | 6 s timeout window | 持续交替输出 `AB`；无 CSR mismatch |
| Phase 0 trace comparison | `cmp` full traces | 完全相同 |

10-seed `add` stress 中 cycles 为 10106～10476，CPI 为 9.229～9.567；不同 seed 的 I/D stall 计数不同，证明两侧随机 timing 确实参与执行。

### 6. 尚未完成的 Phase 1 工作

当前仍是一个过渡结构：`ysyx_main_fsm` 知道 `D_REQ/D_WAIT/D_COMMIT`，地址、size 和 load extension 仍由 core 中的 `ysyx_d_ram_ctrl` 组合产生。

下一独立提交应当：

1. 新建 `ysyx_lsu`，迁入 AGU payload、load extension、request holding、response buffer 和 single-outstanding control；
2. backend 只发送一笔 LSU operation 并等待 completion，不观察外部 `d_req/d_rsp`；
3. 将 data response backpressure 作为 directed test，验证 LSU response buffer；
4. 为 load/store response error 预留字段，但精确 access fault 留到 Phase 3；
5. 再次运行同一 commit trace、35 CPU tests、MMIO workload 和多 seed regression。

因此本 checkpoint 值得单独提交，但不能把整个 Phase 1 标记为完成。

## 2026-09-20：Phase 1 checkpoint 2——single-outstanding LSU

### 1. 提交边界与结论

本轮基于 `93a1189 refactor(npc): expose data request response port`，完成可独立提交的 LSU transaction owner：

```text
backend/main FSM -- op valid/ready --> ysyx_lsu -- d_req/d_rsp --> RAM model
                 <-- result v/r -----
```

- 新增 `ysyx_lsu`，在 operation handshake 时锁存 `{write, address, type, wdata}`；
- LSU 独自管理 `REQ -> WAIT -> RESP` 生命周期，外部 request stall 时 payload 不依赖仍在变化的组合信号；
- LSU 在 memory response handshake 时完成 load sign/zero extension，并将结果缓冲到 backend 接收；
- 原 `ysyx_d_ram_ctrl` 删除，其 size 和 load-extension 职责迁入 LSU；
- `ysyx_main_fsm` 从 `IF_REQ/IF_WAIT/EXEC/D_REQ/D_WAIT/D_COMMIT` 收缩为 `IF_REQ/IF_WAIT/EXEC/LSU_WAIT`，只发起 LSU operation 并等待完成，不再观察 `d_req/d_rsp`。

当前普通 ALU 仍计算 `base + immediate`，即兼任简单 AGU；这与参考核“EXU/AGU 形成请求、LSU 拥有 transaction”的边界一致。简单 transaction 的 size 仍用 `log2(bytes)` 表示，AXI byte strobe 在 Phase 4 adapter 中生成。

### 2. Commit 时序

memory response 先被 LSU 寄存到 `RESP` 状态；下一周期 `lsu_rsp_valid` 已在 active edge 前稳定，backend 同时拉高 `lsu_rsp_ready` 与 `commit_wb`。该 edge 完成 GPR/PC architectural update 和 LSU result handshake。

因此无需 checkpoint 1 的独立 `D_COMMIT` 状态，也没有改变 harness 的约定：`cpu_exec()` 仍可在调用 `single_cycle()` 前采样即将 commit 的 PC、instruction 和 MMIO 属性。指定配置下 `add` 的 cycle 数仍为 6639，说明本次模块抽取没有增加额外气泡。

### 3. 防错与定向验证

NPC Verilator 构建已启用 `--assert`。LSU 内加入三项接口 invariant：

1. external request 被 stall 时，`valid` 与全部 payload 必须保持；
2. backend result 被 stall 时，`valid` 与 read data 必须保持；
3. 没有处于 external response-wait 状态时，不允许 memory 返回 response。

backend FSM 另行断言 memory instruction 只有在 `lsu_rsp_valid` 时才能 commit；single-outstanding 则由 LSU 的互斥 `IDLE/REQ/WAIT/RESP` 状态编码直接保证。

新增 `make -C npc lsu-test` standalone test，显式制造两周期 request backpressure、两周期 backend response backpressure，并检查 signed-byte load extension、第二笔 store payload 和 single-outstanding 生命周期。

这里系统统计中的 data response stall 仍为 0 是设计结果：单 outstanding LSU 在等待 external response 时，其一项 response buffer 必然为空，所以 `d_rsp_ready=1`；memory response 一旦握手，就由 LSU 缓冲并允许 backend 对 result 施加 backpressure。无需为了产生非零计数而故意拒收已经到达的 memory response。

### 4. 验证记录

| Item | Configuration | Result |
| --- | --- | --- |
| RTL lint | `make -C npc lint` | 通过，仅有既存 unused parameter/signal warning |
| LSU directed test | `make -C npc lsu-test` | PASS；协议 assertions 启用 |
| RV32E CPU tests | 默认 seed 42/max-latency 3/ready 75% | 35/35 PASS，DiffTest ON，assertions ON |
| fixed-seed add | seeds 1～10/max-latency 7/ready 50% | 全部 GOOD TRAP |
| unaligned stress | seeds 1～3/max-latency 10/ready 30% | 全部 GOOD TRAP |
| hello/UART | `mainargs=I-love-ysyx` | 输出完整且 GOOD TRAP |
| yield-os/CSR DiffTest | 6 s observation window | 持续交替输出 `AB`，无 mismatch/assertion；timeout 124 为主动终止 |
| architectural trace | `add`, seed 42/max-latency 3/ready 75% | 1095 commits；SHA-256 仍为 `4a87442ab99f4b4d6e362ee8f38dd67c2299954785b211081f051fc03eb4af75` |

Phase 1 至此达到计划 gate。下一提交点进入 Phase 2A：先定义 frontend instruction-context 接口，再抽取 IFU 和最小 IFQ；不要继续在现有 `ysyx_main_fsm` 中增加 fetch 状态。

## 2026-09-20：Phase 2A——elastic IFU 与 2-entry IFQ

### 1. 实现边界

本轮把 instruction fetch 从集中式 FSM 中完整抽出：

```text
imem req/rsp <-> ysyx_ifu(REQ/WAIT/DROP) <-> 2-entry IFQ
                                                |
                                                | if_ctx valid/ready
                                                v
                              transitional backend controller
                                  WAIT_CTX/EXEC/LSU_WAIT
```

- `ysyx_ifu` 独立维护 speculative `fetch_pc_q`、已接受请求的 `request_pc_q` 和 single-outstanding 生命周期；
- IFQ 保存 `{pc, inst}`，对 backend 提供稳定的 `if_ctx_valid/ready/pc/inst/error/pred_*` 边界；第一版 `error=0`、prediction 为 static not-taken；
- backend stall 或等待 LSU 时，IFU 可继续预取直到 2-entry IFQ 满；顺序指令 commit 时可在同一边沿接收下一 context；
- architectural `commit_pc` 仍只在 commit 边沿更新，因此 C++ harness/DiffTest 的既有采样契约未改变；assertion 检查被接受 context 的 PC 必须等于当前或 commit 后的 architectural PC；
- 原 `ysyx_main_fsm` 不再接触 `imem_req/imem_rsp`，暂时只承担 `WAIT_CTX/EXEC/LSU_WAIT` backend 控制，Phase 2B 再由 opbuf/EXU control 取代。

### 2. Credit 与 redirect 语义

IFU 仅在 `ifq_in_ready` 时拉高 request valid。由于 memory side 只有一笔 outstanding，request handshake 等价于为未来 response 预留一个 IFQ entry；等待期间 IFQ 只可能被 backend 消费，不会被其他 producer 填满。因此正常 response 到达时总有 credit，`imem_rsp_ready` 无需随机拉低。

redirect 按请求所处阶段处理：

1. 请求尚未 handshake：压低旧 request valid，并把 fetch PC 改为 target；
2. 请求已经 handshake、response 未返回：清空 IFQ并转入 `DROP`；
3. stale response 返回：正常完成 memory handshake，但不写入 IFQ，随后才从 target 恢复 fetch；
4. redirect 与旧 response 同周期出现：直接消费并丢弃 response，无需多停留一轮 `DROP`。

这种实现没有取消 memory transaction，也不会把旧路径 instruction context 暴露给 backend。代价是 single-outstanding 下必须等 stale response 返回后才能请求 target，后续若引入多 outstanding 再改用 epoch/tag。

### 3. 定向检查与验证

新增 `make -C npc ifu-test`，覆盖 request payload stall、backend stall、IFQ 填满与顺序、无 outstanding redirect、带 outstanding redirect、stale response discard，以及 redirect 与旧 response 同周期发生。IFU/core assertions 另行检查：

- stalled request/context 保持；
- fresh response 必须已有 IFQ credit；
- `DROP` response 不得进入 IFQ；
- redirect commit 不得接收旧 context；
- backend 接收的 context PC 与 architectural PC 边界一致；
- Phase 2A 的静态预测 metadata 自洽。

| Item | Configuration | Result |
| --- | --- | --- |
| RTL lint | `make -C npc lint` | 通过；仅剩既存 `ysyx_gen_imm.inst[6:0]` unused warning |
| primitive / LSU / IFU directed tests | Verilator assertions ON | 全部 PASS |
| RV32E CPU tests | 默认 seed 42/max-latency 3/ready 75% | 35/35 PASS，DiffTest ON |
| add stress | seeds 1～10/max-latency 10/ready 30% | 全部 GOOD TRAP；CPI 10.151～10.464 |
| hello/UART | seed 7/max-latency 10/ready 30% | 输出完整，GOOD TRAP |
| yield-os/CSR DiffTest | seed 9/max-latency 7/ready 50%，5 s window | 持续交替输出 `AB`，无 mismatch/assertion；timeout 124 为主动终止 |
| architectural trace | `add`, seed 42/max-latency 3/ready 75% | 与 Phase 1 完整 trace 逐字节相同，SHA-256 为 `4a87442ab99f4b4d6e362ee8f38dd67c2299954785b211081f051fc03eb4af75` |

### 4. 当前性能观察与 Phase 2B handoff

固定 `add` workload 的 committed instructions 仍为 1095；cycles 从 Phase 1 的 6639 降为 5121，CPI 从 6.063 降为 4.677。instruction requests 从 1096 增至 1258，是 static sequential prefetch 在 212 次 redirect 附近读取年轻/错误路径指令的预期开销；结束时 requests 比 responses 多 1，是仿真在 `ebreak` 前停止时仍有一笔合法 speculative fetch outstanding。

Phase 2A 只完成 frontend elasticization。下一步 Phase 2B 仍需：把当前 instruction register 演化为带完整 decode/reg-read context 的 opbuf，形成明确 EXU/commit control，统一 GPR bypass，并最终删除 `ysyx_main_fsm`。

## 2026-09-20：Phase 2B——opbuf 与集中式 EXU/commit

### 1. 结构变化

本轮删除过渡用的 `ysyx_main_fsm`，形成明确的单发射、顺序 elastic frontend/backend：

```text
IFU + 2-entry IFQ
        |
        | instruction context
        v
decoder + GPR read + WB bypass
        |
        | decoded operation context
        v
1-entry opbuf -> EXU/commit -> ALU / branch / CSR
                     |
                     +-----------> LSU -> dmem
```

- `ysyx_opbuf` 保存 PC、instruction、预测信息、立即数、ALU/branch/memory/CSR 控制、寄存器编号及两个 source operand，共 277 bit context；
- `ysyx_exu` 只消费稳定的 opbuf context，不依赖 IFQ/decoder 的当前组合输出；
- 普通指令组合完成并 commit，memory 指令由 EXU 的 `mem_wait_q` 保持至 LSU result 返回；
- `ysyx_core` 只保留模块互连、architectural PC、GPR/CSR 实例和少量跨边界 assertion。

### 2. 同周期替换与数据相关

普通指令可在 commit 的同一周期释放 opbuf，并由 IFQ head 填入下一项。此时 decoder 读到的 GPR array 仍是 active edge 前的旧值，所以 core 对两个 source operand 分别实现 writeback-to-read bypass：当 `commit_gpr_wen && commit_rd_idx == dec_rs*_idx` 时，送入 opbuf 的是 `commit_wb_data`。

这一 bypass 只解决“上一条在本周期写回、下一条在本周期入队”的 RAW；执行期间没有多条在途 backend 指令，因此不需要通用 forwarding network 或 scoreboard。

### 3. Commit、memory 与 redirect

- ALU/branch/CSR 的结果、GPR writeback、CSR/trap/mret event、memory metadata 和 redirect 都由 EXU 的同一 commit 边界产生；
- load/store 只 issue 一次 LSU operation，等待期间 opbuf context 保持，收到 LSU result 后才 commit；
- branch/jump/trap/mret commit 时统一生成 `redirect_valid/redirect_target`，IFU 同步 flush IFQ，并丢弃已握手但尚未返回的旧路径 fetch；
- redirect 指令本身是当前最老 opbuf entry，会随 commit 正常出队；同周期 IFU 不允许年轻 context 进入 opbuf，因此无需 flush 正在完成的 entry；
- architectural `commit_pc` 仍只在 commit edge 更新，保持 C++ harness/DiffTest 的原采样契约。

新增 assertions 检查 opbuf/LSU request stall stability、memory commit 必须有 LSU result、commit PC 与 architectural PC 一致、同周期 GPR bypass 正确，以及静态预测 metadata 自洽。

### 4. 验证记录

| Item | Configuration | Result |
| --- | --- | --- |
| RTL lint | `make -C npc lint` | 通过；仅剩既存 `ysyx_gen_imm.inst[6:0]` unused warning |
| directed tests | primitive / LSU / IFU / EXU，Verilator assertions ON | 全部 PASS；EXU 覆盖 ALU、taken branch、CSR、stalled load、trap、mret |
| RV32E CPU tests | 默认 seed 42/max-latency 3/ready 75% | 35/35 PASS，DiffTest ON |
| add stress | seeds 1～10/max-latency 10/ready 30% | 全部 GOOD TRAP |
| hello/UART | seed 7/max-latency 10/ready 30% | 输出完整，GOOD TRAP |
| yield-os/CSR DiffTest | seed 9/max-latency 7/ready 50%，5 s window | 持续交替输出 `AB`，无 mismatch/assertion；timeout 124 为主动终止 |
| architectural trace | `add`, seed 42/max-latency 3/ready 75% | 与 Phase 2A 基线逐字节相同，SHA-256 为 `4a87442ab99f4b4d6e362ee8f38dd67c2299954785b211081f051fc03eb4af75` |

固定 workload 仍为 1095 commits、5121 cycles、CPI 4.677，说明本次 backend 分层没有引入额外气泡。Phase 2 至此完成，下一步按计划进入 Phase 3：让 instruction/data access error 走精确 architectural trap，而不是由 harness 直接终止仿真。
