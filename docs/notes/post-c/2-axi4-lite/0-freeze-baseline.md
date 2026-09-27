# AXI4-Lite 阶段 0：基线与接口冻结

> 冻结日期：2026-09-28  
> Git baseline：`a9b47e901d1fdf40cb3ef76b904e0a7130b007d5`  
> 状态：Stage 0 complete；尚未修改 RTL 数据通路或加入 adapter。

## 1. 冻结目的

本文件是 AXI4-Lite 改造前后的比较依据，也是 IFU/LSU、adapter 与测试环境之间的
接口契约。后续实现可以改变 cycle timing，但不得无记录地改变：

- architectural commit sequence；
- local request/response 的 ownership；
- byte lane、错误和 reset 语义；
- 本文列出的 AXI signal direction、width 和 handshake 规则。

规范依据为 ARM IHI 0022H 的 A2、A3 和 Part B。仓库已有完整手册及
[`AXI4-Lite 摘录`](../../../ref-spec/b-amba-axi4-lite-extract.pdf)，因此当前没有资料阻塞。

## 2. 改造前功能与性能基线

当前 HEAD 使用 C++ single-outstanding variable-latency RAM model。2026-09-28 的复测结果：

| 检查项 | 结果 |
| --- | --- |
| RTL lint | PASS；仅有既存的 `ysyx_gen_imm.inst[6:0]` unused warning |
| primitive / IFU / LSU / EXU directed tests | 全部 PASS，assertions ON |
| fetch/load/store access-fault tests | 全部 PASS，`mcause=1/5/7` |
| RV32E CPU tests | 改造前 35/35 PASS，DiffTest ON |
| fixed-seed `add` | seeds 1～10、max latency 7、ready 50%，全部 GOOD TRAP |

主要复现命令：

```bash
make -C npc lint primitive-test ifu-test lsu-test exu-test access-fault-test
make -C am-kernels/tests/cpu-tests ARCH=riscv32e-npc run
make -C npc seed-regress \
  IMG=../am-kernels/tests/cpu-tests/build/add-riscv32e-npc.bin \
  RAM_SEEDS='1 2 3 4 5 6 7 8 9 10' \
  RAM_MAX_LATENCY=7 RAM_READY_PERCENT=50
```

这里的 35/35 包含旧 `unalign`：它在 `buf + 3` 执行跨 32-bit 边界的 word
load/store。该行为由旧 C++ RAM 偶然支持，不是冻结后的 CPU/AXI contract；后续普通
成功路径回归为其余 34 项，并用精确 misaligned-exception tests 替代该项。

### 2.1 固定性能样本

workload 为 `cpu-tests/add`，DiffTest ON，RAM seed 42、max latency 3、request ready
75%。结果如下：

| Metric | Baseline |
| --- | ---: |
| committed instructions | 1095 |
| cycles | 5121 |
| CPI | 4.677 |
| redirects | 212 |
| IF request stall / response wait | 431 / 1889 |
| D request stall / response wait | 76 / 426 |
| IF transactions | 1258 requests / 1257 responses |
| D transactions | 282 = 243 loads + 39 stores |

最后一笔 speculative fetch 在 `ebreak` 停止仿真时仍 outstanding，因而 IF request 比
response 多 1；这不是 transaction 丢失。

### 2.2 Commit trace 基线

trace 格式为 v3，共 1095 条 commit：

```text
full trace SHA-256:
a066cd4ab6b90481d155cdabd533de2138e3e6c6c3e192fe653835772cf42c66

nr/pc/inst/npc/architectural_state_hash SHA-256:
bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284
```

AXI adapter 会改变 `cycles_since_commit` 和 `stall_mask`，因此阶段验收比较前五个
architectural fields；完整 trace hash 仅用于复现改造前的 cycle-accurate baseline。

复现命令：

```bash
./npc/build/Vysyx_core \
  -d nemu/build/riscv32-nemu-interpreter-so -b \
  --ram-seed=42 --ram-max-latency=3 --ram-ready-percent=75 \
  --commit-trace=/tmp/npc-axi-stage0-add.trace \
  am-kernels/tests/cpu-tests/build/add-riscv32e-npc.bin

awk '!/^#/ {print $1, $2, $3, $4, $5}' \
  /tmp/npc-axi-stage0-add.trace | sha256sum
```

## 3. Local transaction 接口

local 接口保持现状，IFU/LSU 不感知 AXI channel。所有 payload 均在 request
handshake 时由 adapter 接管；adapter 必须把 response 保持到 local response handshake。

### 3.1 IFU 与 adapter

| Signal | Adapter direction | Width | Contract |
| --- | --- | ---: | --- |
| `imem_req_valid` | input | 1 | request valid |
| `imem_req_ready` | output | 1 | adapter 可接收 request |
| `imem_req_addr` | input | 32 | 取指地址，必须 4-byte aligned |
| `imem_rsp_valid` | output | 1 | response valid |
| `imem_rsp_ready` | input | 1 | IFU 可接收 response |
| `imem_rsp_data` | output | 32 | 完整 instruction word |
| `imem_rsp_error` | output | 1 | AXI read response 非 OKAY |

一笔 `imem_req_valid && imem_req_ready` 对应且只对应一个 AR handshake 和一个 local
response。redirect 不取消已被 adapter 接受的 transaction；IFU 继续负责消费并丢弃 stale
response。

### 3.2 LSU 与 adapter

| Signal | Adapter direction | Width | Contract |
| --- | --- | ---: | --- |
| `dmem_req_valid` | input | 1 | request valid |
| `dmem_req_ready` | output | 1 | adapter 可接收 request |
| `dmem_req_write` | input | 1 | 0=load，1=store |
| `dmem_req_addr` | input | 32 | 原始 effective address |
| `dmem_req_size` | input | 2 | log2(bytes)：0/1/2 对应 byte/half/word |
| `dmem_req_wdata` | input | 32 | 未做 lane shift 的 GPR data |
| `dmem_rsp_valid` | output | 1 | response valid；store 也必须返回 response |
| `dmem_rsp_ready` | input | 1 | LSU 可接收 response |
| `dmem_rsp_data` | output | 32 | load 数据右移至 bit 0；store 时为 0 |
| `dmem_rsp_error` | output | 1 | AXI `RRESP/BRESP` 非 OKAY |

LSU 仍负责 load sign/zero extension。每笔 accepted request 只产生一次 local response；
第一版每个 adapter 最多一笔 outstanding。

## 4. AXI4-Lite master 接口

adapter 模块内部 AXI 端使用 `m_axi_*`；接到 `ysyx_core` 顶层时去掉 `m_`，分别加
`ifu_axi_*` 或 `lsu_axi_*` 前缀。clock/reset 继续使用工程统一的 `clk`、`rst_n`，语义
对应 AXI `ACLK`、`ARESETn`。

### 4.1 IFU read-only master

| Adapter port | Core top port | Dir. | Width |
| --- | --- | --- | ---: |
| `m_axi_arvalid` | `ifu_axi_arvalid` | out | 1 |
| `m_axi_arready` | `ifu_axi_arready` | in | 1 |
| `m_axi_araddr` | `ifu_axi_araddr` | out | 32 |
| `m_axi_arprot` | `ifu_axi_arprot` | out | 3 |
| `m_axi_rvalid` | `ifu_axi_rvalid` | in | 1 |
| `m_axi_rready` | `ifu_axi_rready` | out | 1 |
| `m_axi_rdata` | `ifu_axi_rdata` | in | 32 |
| `m_axi_rresp` | `ifu_axi_rresp` | in | 2 |

`ARPROT=3'b101`：privileged、secure、instruction。

### 4.2 LSU read/write master

| Adapter port suffix | Core top prefix | Dir. | Width |
| --- | --- | --- | ---: |
| `m_axi_awvalid/awaddr/awprot` | `lsu_axi_*` | out | 1 / 32 / 3 |
| `m_axi_awready` | `lsu_axi_*` | in | 1 |
| `m_axi_wvalid/wdata/wstrb` | `lsu_axi_*` | out | 1 / 32 / 4 |
| `m_axi_wready` | `lsu_axi_*` | in | 1 |
| `m_axi_bvalid/bresp` | `lsu_axi_*` | in | 1 / 2 |
| `m_axi_bready` | `lsu_axi_*` | out | 1 |
| `m_axi_arvalid/araddr/arprot` | `lsu_axi_*` | out | 1 / 32 / 3 |
| `m_axi_arready` | `lsu_axi_*` | in | 1 |
| `m_axi_rvalid/rdata/rresp` | `lsu_axi_*` | in | 1 / 32 / 2 |
| `m_axi_rready` | `lsu_axi_*` | out | 1 |

`ARPROT=AWPROT=3'b001`：privileged、secure、data。AW 与 W 是独立 channel，任何一方
都不得等待另一方 READY 才拉高 VALID；adapter 必须分别记录两个 handshake。

## 5. Alignment 与 byte lane

### 5.1 Architectural misaligned exception

冻结后的合法性判断为：

```text
byte:     always aligned
halfword: addr[0]   == 0
word:     addr[1:0] == 0
```

非法 load 产生 `mcause=4`，非法 store 产生 `mcause=6`。异常在 EXU 根据 effective
address 判定，必须满足：

- 不拉高 LSU/local/AXI request valid；
- `mepc` 为 faulting instruction PC，并 redirect 到 `mtvec`；
- 不产生 GPR write、store side effect 或普通 CSR/mret side effect；
- trace 保留 `mem_valid=1` 和原始 effective address，`mem_error=0`；cause 用于表明
  这是 address exception，而不是 AXI response error。

DiffTest 在该 commit 调用 reference `difftest_raise_intr(4/6)`，不让 reference 执行
faulting load/store。该 RTL 和定向测试在 LSU adapter 阶段开始时实现。

### 5.2 合法窄访问

AXI4-Lite 没有 AxSIZE，所有访问均使用 32-bit data bus。合法 data request 使用：

```text
bus_addr = {req_addr[31:2], 2'b00}
WSTRB    = base_strobe << req_addr[1:0]
WDATA    = req_wdata << (8 * req_addr[1:0])
rsp_data = RDATA >> (8 * req_addr[1:0])
```

| Access | `addr[1:0]` | `WSTRB` | 有效 `WDATA` lane |
| --- | --- | --- | --- |
| byte | 00/01/10/11 | `0001/0010/0100/1000` | 对应一个 byte lane |
| halfword | 00/10 | `0011/1100` | 低/高 halfword |
| word | 00 | `1111` | 全部 lanes |

IFU 的 `ARADDR` 等于已对齐的 `imem_req_addr`。adapter 为 local alignment contract 加
assertion，但不能用 silent address truncation 掩盖 core bug。

当前选择解决的是既有 `unalign` data-access 语义。RV32I 在 misaligned branch/jump target
上还要求 instruction-address-misaligned exception（`mcause=0`）；当前 RTL 尚未补齐该
独立 ISA 项。它不阻塞对齐取指的 adapter 开发，但不能被 AXI adapter 伪装成 read error，
后续 ISA compliance 收尾时应在发出错误目标的控制流指令处精确处理。

## 6. Response error 和 reset

response 编码统一为：

```text
2'b00 OKAY   -> local rsp_error = 0
2'b01 EXOKAY -> local rsp_error = 1  // AXI4-Lite 不支持
2'b10 SLVERR -> local rsp_error = 1
2'b11 DECERR -> local rsp_error = 1
```

read error 映射为 instruction/load access fault `mcause=1/5`；write error 映射为 store
access fault `mcause=7`。这类错误发生在 AXI transaction 返回之后，与发请求前发现的
misaligned exception `4/6` 分离。

reset 契约如下：

- `rst_n` 低有效，允许异步拉低，只允许在 `clk` 上升沿同步释放；
- reset 时 `ARVALID/AWVALID/WVALID=0`，本设计同时令 `RREADY/BREADY=0`；
- reset 清除 adapter outstanding、AW/W completion 和 response buffer；
- 所有 master/slave/core 同域复位，reset 前未完成 transaction 被整体放弃，不生成 local response；
- reset 释放后的第一个上升沿之后才允许重新发出 AXI VALID。

每个 channel 均遵守 `VALID && READY` handshake：发送方的 VALID 不依赖 READY；一旦
VALID 拉高，在 handshake 前 VALID 和 payload 必须保持稳定。slave 的 RVALID 只能在
AR handshake 后出现；BVALID 只能在 AW、W 都 handshake 后出现。

## 7. Stage 0 出口

- [x] Phase 3 functional regression 可复现；
- [x] 固定 workload 的 cycles/CPI/stall baseline 已记录；
- [x] architectural trace hash 已记录；
- [x] local 与两套 AXI4-Lite master 接口已冻结；
- [x] alignment、lane、response error、single-outstanding 和 reset 语义已冻结；
- [x] 跨边界访问策略确定为 precise address-misaligned exception；
- [x] 当前无阻塞项，可以进入 IFU adapter 阶段。
