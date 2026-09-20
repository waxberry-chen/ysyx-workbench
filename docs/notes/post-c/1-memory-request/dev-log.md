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

Phase 2 引入 IFQ/opbuf 后再把 frontend flush 变成实际 counter，并增加可强制 `if_rsp_ready=0` 的 directed response-backpressure 测试。
