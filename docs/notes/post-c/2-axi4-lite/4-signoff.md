# AXI4-Lite 阶段 4：回归与阶段验收

> Sign-off 日期：2026-09-28  
> RTL/仿真基线：`94cf9ac`（Stage 3）  
> 状态：PASS；Milestone `2-axi4-lite` closed。

## 1. 验收结论

NPC 已完成从自定义 core-top memory req/rsp 到两套 AXI4-Lite master 的迁移。本轮
sign-off 未发现 functional、DiffTest、protocol assertion 或 transaction accounting
问题，可以将当前接口作为后续 Arbiter/Xbar 的稳定输入。

一键回归入口位于 `npc/scripts/tests.mk`：

```bash
make -C npc axi4lite-signoff
```

默认参数为：

```text
random seeds        = 1..10
max response latency= 7 cycles
channel ready       = 50%
AM smoke duration   = 10 seconds/case
```

构建和运行日志位于被忽略的 `npc/build/`，不是需要提交的源码资产。

## 2. Sign-off Matrix

| Layer | Check | Result |
| --- | --- | --- |
| Static | `ysyx_core` lint | PASS；仅有既存 `ysyx_gen_imm.inst[6:0]` unused warning |
| Primitive | ready/valid buffer directed test | PASS |
| IFU | local req/rsp、redirect、stale response | PASS |
| LSU | load/store、response holding、access error | PASS |
| EXU | commit、redirect、memory exception | PASS |
| IFU adapter | AR stall、R delay/backpressure、error、reset | PASS |
| IFU integration | redirect before/after AR、stale AXI response | PASS |
| LSU adapter | AW-first、W-first、lane、response、reset、去重 | PASS |
| Access fault | fetch/load/store cause 1/5/7 | PASS |
| Misaligned | load/store cause 4/6、无 data AXI request | PASS |
| ISA regression | RV32E CPU tests，排除旧 `unalign` | 34/34 PASS，DiffTest ON |
| Random timing | seeds 1～10，latency 7，ready 50% | PASS |
| UART | `hello` 和 `mainargs=I-love-ysyx` | PASS，GOOD TRAP |
| RTC | `am-tests mainargs=t` 连续输出时间 | PASS，预期 timeout |
| Trap/context | `yield-os` 持续交替输出 `AB` | PASS，预期 timeout，无 mismatch |

`unalign` 不计入失败项。它要求跨 32-bit boundary 的非对齐 word load/store 成功，与本
milestone 已冻结的 precise address-misaligned exception 策略冲突；cause 4/6 定向测试
取代了它。

## 3. 可重复回归入口

聚合目标由以下子目标组成：

```text
axi4lite-directed-regress
  lint + primitive/IFU/LSU/EXU + adapter + exception tests

axi4lite-cpu-regress
  34 CPU tests with DiffTest

axi4lite-trace-test
  fixed add workload + transaction counts + architectural hash

seed-regress
  fixed add workload under ten random channel schedules

axi4lite-am-smoke
  UART hello + RTC + yield-os
```

可以单独运行子目标缩短日常迭代时间；修改 adapter、core top 或 C++ AXI slave 后再运行
完整 `axi4lite-signoff`。

`cpu-tests` 原有聚合 Makefile 可能在个别子项记录 `FAIL` 后仍以成功状态返回，因此新的
入口不只检查进程退出码，还检查不存在 `FAIL` 且恰好出现 34 条 `PASS`，避免回归假阳性。

## 4. Architectural Equivalence

固定 workload：`cpu-tests/add`，DiffTest ON，seed 42、max latency 3、ready 75%。

```text
committed instructions = 1095

architectural fields SHA-256:
bbf8496edf2329d695eb4437641ced89bba9cf0b6006f1a0b5955c32941e9284

full Stage 3 trace SHA-256:
af1a6979fa387c6fb1795cfb1079ae2073c9004f5c1c9cda97dbaed643b7ba6a
```

architectural hash 只覆盖 trace 中的 instruction number、PC、instruction、next-PC 和
architectural state hash，与 Stage 0 完全一致。full hash 还包括 cycles/stall/exception
metadata，仅作为当前全寄存实现的 cycle-level 样本。

## 5. Transaction Accounting

同一固定样本得到：

| Interface | Requests | Responses | Errors |
| --- | ---: | ---: | ---: |
| IFU AXI read | 1310 AR | 1310 R | 0 |
| LSU AXI read | 243 AR | 243 R | 0 |
| LSU AXI write | 39 AW + 39 W | 39 B | 0 |
| LSU total local transactions | 282 | 282 | 0 |

检查结果说明：

- 每笔 accepted fetch/load 都有且只有一个 read response；
- 每笔 store 的 AW/W 都各 handshake 一次，并只产生一个 B response；
- AW/W 任一 channel 先完成时，另一 channel stall 不会重复已完成 channel；
- backend store 在 AW/W 汇合后只执行一次，等待 B handshake 不重复 side effect；
- address-misaligned load/store 在 EXU 截断，data AXI transaction 数为 0。

## 6. Performance Delta

| Metric | Stage 0 local req/rsp | Stage 3 AXI adapter | Delta |
| --- | ---: | ---: | ---: |
| committed instructions | 1095 | 1095 | 0 |
| cycles | 5121 | 7801 | +2680 |
| CPI | 4.677 | 7.124 | +2.447 |
| IF request stall | 431 | 467 | +36 |
| IF response wait | 1889 | 1952 | +63 |
| D request stall | 76 | 105 | +29 |
| D response wait | 426 | 444 | +18 |

cycles 增长约 52%，主要来自全寄存 adapter 的 local request capture、AXI request、AXI
response capture 和 local response transfer，而不是外部 channel stall。因此不能用表中
四项 stall delta 直接解释全部 2680 cycles；adapter 内部转发状态目前没有单独归入
`stall_mask`。

该性能不是最终优化目标，而是协议正确、容易验证的基线。Optional fall-through/skid
优化必须先结合综合 timing 判断，且不得改变本文件冻结的外部接口和 transaction 语义。

## 7. 冻结接口与语义

### 7.1 IFU read-only master

```text
ifu_axi_arvalid/arready/araddr[31:0]/arprot[2:0]
ifu_axi_rvalid/rready/rdata[31:0]/rresp[1:0]
```

### 7.2 LSU read/write master

```text
lsu_axi_arvalid/arready/araddr[31:0]/arprot[2:0]
lsu_axi_rvalid/rready/rdata[31:0]/rresp[1:0]
lsu_axi_awvalid/awready/awaddr[31:0]/awprot[2:0]
lsu_axi_wvalid/wready/wdata[31:0]/wstrb[3:0]
lsu_axi_bvalid/bready/bresp[1:0]
```

冻结语义如下：

- IFU/LSU 各 single-outstanding；两个 master 之间仍可独立活动；
- `VALID` 不依赖 `READY`，stall 期间 payload 保持稳定；
- reset 时 master request VALID 和 slave response VALID 均为 0；
- IFU `ARPROT=3'b101`，LSU `ARPROT/AWPROT=3'b001`；
- data AXI address 为 4-byte aligned bus address，窄写由 `WSTRB/WDATA` lanes 表达；
- `RRESP/BRESP=OKAY` 为成功，其余编码映射为 access fault；
- misaligned exception 在发出 AXI request 前产生，不伪装为 slave response error；
- redirect 不取消已经 accepted 的 fetch transaction，由 IFU 消费并丢弃 stale response。

后续 Arbiter 需要保持每个 transaction 的 channel ownership，特别是不能把不同 master
或不同 store 的 AW/W 错误配对。

## 8. 已知边界

以下项目不阻塞本 milestone：

- Core 暂时暴露两套 master，尚未实现共享 external master 的 Arbiter；
- 尚无 Xbar、RTL RAM/CLINT/UART slave，这些属于后续 interconnect milestone；
- adapter 暂不支持 burst、AXI ID、多 outstanding 或 cache；
- instruction-address-misaligned exception（cause 0）仍是独立 ISA compliance 待办；
- C++ slave 是验证模型，不是可综合 AXI slave；
- 全寄存 adapter 的固定延迟较高，暂不为了 CPI 在 SoC 接入前引入 fast path。

此外，本次关闭的是 `plan.md` 定义的功能与协议 sign-off。roadmap 中更深的
machine-readable functional coverage、随机 response-code injection 和 bounded formal
尚未声称完成；它们应与下一阶段 Arbiter/Xbar 的 system-level test plan 一并实施，避免
现在为即将改变的总线拓扑重复搭建验证结构。

## 9. 下一步

Milestone `2-axi4-lite` 到此关闭。下一阶段进入
`3-axi4-lite-interconnect`：先明确 two-master/one-slave arbitration contract，再实现
Arbiter、地址 decode/Xbar 和最小 RTL slave，并以本 sign-off 的两套 master interface
作为不随意修改的输入边界。
