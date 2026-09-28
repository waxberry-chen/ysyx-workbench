# AXI4-Lite 阶段 1：IFU Adapter 工作记录

> 完成日期：2026-09-28  
> 基线提交：`21abe761da1a67c728a4e50add03ee5f5bdf2175`  
> 状态：Stage 1 complete；无阻塞项。

## 1. 完成内容

新增 `ysyx_ifu_axi4lite_adapter`，在现有 IFU local request/response 与 AXI4-Lite
`AR/R` channel 之间完成转换：

```text
ysyx_ifu
   │ imem req/rsp
   ▼
ysyx_ifu_axi4lite_adapter
   │ AR/R
   ▼
AXI4-Lite slave
```

本阶段只实现和独立验证 adapter，尚未修改 `ysyx_core` 顶层接口，也未替换当前 C++
RAM model。这样可以先关闭协议模块自身的风险，再在阶段 3 统一完成 core 和仿真环境集成。

主要文件：

| File | Purpose |
| --- | --- |
| `npc/vsrc/bus/ysyx_ifu_axi4lite_adapter.sv` | IFU read-only AXI4-Lite adapter |
| `npc/tests/ysyx_ifu_axi4lite_adapter_tb.sv` | adapter standalone directed test |
| `npc/tests/ysyx_ifu_axi4lite_adapter_integ_tb.sv` | IFU、adapter 和 scripted AXI slave integration test |
| `npc/scripts/tests.mk` | 新增两个独立测试目标 |
| `npc/filelist.f` | 纳入 RTL source list |

## 2. RTL 设计

### 2.1 全寄存 transaction FSM

adapter 采用四态、single-outstanding 状态机：

```text
IDLE -> SEND_AR -> WAIT_R -> HOLD_RSP -> IDLE
```

| State | Ownership / behavior |
| --- | --- |
| `IDLE` | 接收一笔 local request 并保存 address |
| `SEND_AR` | 保持 `ARVALID/ARADDR/ARPROT`，直到 AR handshake |
| `WAIT_R` | 保持 `RREADY`，等待并保存 `RDATA/RRESP` |
| `HOLD_RSP` | 保持 local response，直到 IFU handshake |

local request 与 AR、R 与 local response 之间都经过寄存器，因此：

- AXI output 不组合依赖 AXI input；
- AR 和 local response 均能独立承受 backpressure；
- 一笔 request 的 address 和 response 不会被下一笔 transaction 覆盖；
- 基础版本会在 request/response 两侧各增加一个固定转发周期，性能优化留到基础版本集成验收之后。

### 2.2 协议与错误语义

- `ARPROT=3'b101`，表示 privileged、secure、instruction；
- `RRESP=OKAY` 时 `imem_rsp_error=0`；其余三个编码均映射为 1；
- adapter 不取消已接受的 transaction；redirect 和 stale response 仍由 IFU 的 `DROP` 状态处理；
- reset 清空 outstanding transaction 和 response buffer，并压低 AXI VALID/READY 及 local handshake 输出；
- local request address 必须 4-byte aligned，adapter 用 assertion 检查该 core-side contract。

### 2.3 Assertions

当前属性覆盖：

- local instruction request 必须对齐；
- `ARVALID && !ARREADY` 时 address/control 保持稳定；
- local response backpressure 时 valid/data/error 保持稳定；
- AXI R response 必须对应一笔已经完成 AR handshake 的 outstanding read；
- 非 `IDLE` 状态不得接收第二笔 local request。

这些属性检查 transaction ownership 和 payload holding，不替代 directed test 的数据与
control-flow scoreboard。

## 3. 验证内容

### 3.1 Standalone adapter test

`make -C npc ifu-axi4lite-adapter-test` 覆盖：

| Scenario | Check |
| --- | --- |
| AR backpressure | `ARVALID/ARADDR/ARPROT` 连续多个周期稳定 |
| delayed R | AR 完成后可以任意延迟返回数据 |
| local response backpressure | buffered data/error 保持到 IFU 接收 |
| response encoding | `00` 成功，`01/10/11` 全部转为 error |
| single outstanding | transaction 完成前 `imem_req_ready=0` |
| reset during `SEND_AR` | 放弃未完成 transaction，接口恢复到 idle |

### 3.2 IFU integration test

`make -C npc ifu-axi4lite-adapter-integ-test` 使用 scripted AXI read slave 覆盖：

1. redirect 发生在 AR handshake 前；
2. redirect 发生在 AR handshake 后、等待 R 期间；
3. redirect 与 AXI R handshake 发生在同一上升沿；
4. redirect 与 buffered local response 到达 IFU 同周期；
5. stale response 不进入 IFQ，下一笔请求从最新 redirect target 发出；
6. 随后的正常 response 携带正确 PC、instruction 和 prediction metadata 进入 IFQ；
7. 五笔 request 均恰好产生一次 AR 和一次 R handshake。

全寄存 adapter 下，AXI R handshake 后一个周期才出现 local response。因此第 3 项会让
IFU 先进入 `DROP`，随后消费 buffered response；第 4 项则可在 redirect 当拍消费 response，
不额外进入 `DROP`。两条路径都必须保持旧请求不可取消且 stale instruction 不可见。

## 4. 回归结果

| Verification | Result |
| --- | --- |
| adapter standalone test | PASS，assertions ON |
| IFU + adapter integration test | PASS，5 AR / 5 R transactions |
| adapter lint | PASS，无 warning |
| core lint | PASS；仅有既存 `ysyx_gen_imm.inst[6:0]` unused warning |
| primitive / IFU / LSU / EXU directed tests | 全部 PASS |
| instruction/load/store access-fault tests | 全部 PASS |
| 改造前 core CPU tests | 35/35 PASS，DiffTest ON |

adapter 尚未接入 core，因此固定 `cpu-tests/add` 应与 Stage 0 cycle-accurate baseline
完全相同，复测结果确实保持：

```text
commits = 1095
cycles  = 5121
CPI     = 4.677

full trace SHA-256:
a066cd4ab6b90481d155cdabd533de2138e3e6c6c3e192fe653835772cf42c66

architectural fields SHA-256:
bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284
```

沙箱中的默认 ccache 目录不可写，验证时临时设置了：

```bash
CCACHE_DIR=/tmp/ysyx-ccache \
CCACHE_TEMPDIR=/tmp/ysyx-ccache-tmp \
make -C npc ifu-axi4lite-adapter-test \
  ifu-axi4lite-adapter-integ-test
```

这是验证环境差异，不需要写入工程 Makefile。

## 5. 阶段结论

Stage 1 已关闭，冻结接口没有变化。当前没有阻塞项，可以进入 Stage 2：

1. 先实现 load/store address-misaligned 精确异常，确保 `mcause=4/6` 且不发出 LSU/AXI request；
2. 实现 LSU AXI4-Lite adapter 的 read path；
3. 用独立状态跟踪 AW/W handshake，再等待 B response；
4. 验证 byte/half/word lane、AW-first/W-first、response error 与 backpressure。
