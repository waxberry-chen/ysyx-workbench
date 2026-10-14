# M3 S2：Xbar 与 default DECERR slave

> 2026-10-14；状态：**S2 PASS，可进入 S3 SRAM/UART/CLINT**。
> 运行起点：`be83ff5`，初始工作区干净；本轮实现尚未提交，源码 hash 与归档见 [s2-manifest.json](s2-manifest.json)。

## 1. 实现与选择依据

新增 [ysyx_axi4lite_xbar.sv](../../../../npc/vsrc/bus/ysyx_axi4lite_xbar.sv) 和 [ysyx_axi4lite_decerr.sv](../../../../npc/vsrc/bus/ysyx_axi4lite_decerr.sv)。遵循 [plan.md §3–4](plan.md)，不改变 S1 Arbiter 或 Core 的接口契约。

Xbar 是一个上游、四个下游的 AXI4-Lite 路由器，下游使用 `[0:3]` unpacked 数组；端口顺序固定为 **0 SRAM、1 UART、2 CLINT、3 DECERR**。它采用与 Arbiter 相同的全寄存、局部单事务结构：先预留 read/write 类型，再接受请求，缓冲后转发，响应进入寄存器，直到上游 R/B 握手才释放。独立输入同时提出 read/write 时采用事务粒度 RR，reset 后 read 优先；实际 Arbiter 输出不会同时发出两种事务。

| 决策 | 工作方式与依据 | 代价 / 边界 |
| --- | --- | --- |
| 地址范围译码 | AR/AW 握手时按完整 32-bit 地址比较左闭右开区间；SRAM 结束地址用 33-bit 加法 | 不使用低位截断产生镜像地址；参数不要求是 2 的幂次 |
| target 锁存 | 地址握手时保存 target，并置 `target_valid`；直到上游 response 完成保持 | response backpressure 会占住服务槽 |
| W-first | 只记录 WDATA/WSTRB；没有 AW 时 target 无效，不向任何端口发 W | 收齐 AW/W 后才转发，增加固定缓冲延迟 |
| AW/W 独立发送 | 各自维护 sent，先握手的通道停止发送，另一条保持 | 保留完整写事务上下文，无提前转发 AW 优化 |
| 唯一响应路径 | 只有目标端口可看到请求 VALID、响应 READY；选中的 RDATA/RRESP/BRESP 缓冲后原样返回 | 不支持 read/write 并行、多 outstanding 或跨 target 并发 |
| default 错误终结 | 地址未映射时仍完成 AXI 事务，返回 DECERR；错误 read 数据为 0 | 不是 harness abort，也没有存储或设备副作用 |

SRAM 默认范围为 `[0x80000000, 0x80100000)`，UART 为 `[0xa00003f8, 0xa0000400)`，CLINT 为 `[0xa0000048, 0xa0000050)`。配置守卫在仿真启动时拒绝零容量、非 word-aligned 容量、地址溢出及 MMIO 重叠。

**Xbar 不检查设备权限或静默对齐地址。** 映射范围内的未对齐地址、UART 保留 word、MMIO 取指仍按地址送到对应 slave；S3 slave 负责生成 SLVERR。测试中 scripted slave 的错误码及错误数据用于检验透传，不代表已实现设备权限检查。

DECERR slave 同样先预留类型，独立接受 AW/W；因为所有请求都拒绝，只需保存通道已接受标志，不必保存无用 payload。写必须等两条通道都握手才产生 B，`WSTRB=0` 也返回 DECERR。响应生成不等待 RREADY/BREADY，并持续保持至握手。reset 清空事务状态，关闭握手控制；所有参与者共同 reset，旧响应不进入新 epoch。

这些选择继续以容易验证的归属边界为基线，并未证明时延、面积或功耗最优。Arbiter 与 Xbar 逐层缓存的固定延迟在 S4 集成后测量，综合/STA 仍属后续工作。

## 2. 验证环境与实测结果

[axi4lite_xbar_tb.cpp](../../../../npc/tests/axi4lite_xbar_tb.cpp) 使用独立 read/write driver、四路 scripted slave 和外部握手 scoreboard；[test wrapper](../../../../npc/tests/axi4lite_xbar_test_top.sv) 也可把第四路接到真实 DECERR RTL。wrapper 的 tap 只观察端口连线，不暴露内部 state/target。路由预期由定向地址表或生成事务指定，不读取 DUT 译码结果。

scoreboard 检查请求只发送一次、payload/PROT/WSTRB 不变、目标唯一、没有地址时不转发、响应类型/数据/错误码正确，以及响应完成前不接收新事务。上游握手后主动改变输入 payload，用于发现遗漏锁存。未选端口加入响应噪声，专门检查隔离；这是健壮性负向激励，不把无请求响应说成合法 slave 行为。SVA 检查 target/type holding、AW/W 汇合、未选端口安静、下游请求及上游响应 holding。

[axi4lite_decerr_tb.cpp](../../../../npc/tests/axi4lite_decerr_tb.cpp) 直接验证 default slave，避免 Xbar 收齐 AW/W 后发送掩盖 slave 自己的 W-first 支持。它还检查不能提前返回 B、不能重复接受或响应、read/write 竞争、response backpressure 和 reset 恢复。

| 检查 | 结果 |
| --- | --- |
| SVA strict lint / `-DSYNTHESIS` 分支 lint | PASS；前者仅沿用 S1 的 `SYNCASYNCNET` 定向豁免，后者无告警；不是实际综合 |
| T05 地址边界 | 18 个地址 × read/write × PROT 1/5，共 72 笔通过；包括各窗口前一字节、首 word、末 word、末字节、结束地址、0、最大地址及 SRAM 镜像风险地址 |
| AW/W 顺序 | 4 routes × ingress 3 种 × egress 3 种，共 36 个 bin 命中 |
| 错误与隔离 | 4 routes × read/write × OKAY/SLVERR/DECERR，共 24 个透传 bin 命中；真实 default 返回 DECERR/RDATA=0，随后 mapped 请求恢复 |
| stalls / 字段 | 五通道均命中 stall；定向 64 周期 READY/response delay/response hold；全部 16 个 WSTRB，随机 PROT 和数据 |
| Xbar reset | 每路 12 个阶段，共 48 个场景；另有真实 default 连接的 read/write reset 恢复 |
| Xbar 随机 | seeds 1–10，各完成 1000 笔；独立 read/write 持续竞争检查最多被另一类型超越一笔 |
| Xbar 总记账（每个容量配置） | **10488 accepted = 10446 completed + 42 reset-aborted**；drain 后无 outstanding；215 个命中 coverage bin |
| DECERR 独立测试 | **328 accepted = 317 completed + 11 reset-aborted**；65 个命中 bin；AW-first/same/W-first × 全部 WSTRB × hold 0/1/64 |
| 容量对照 | 默认 1 MiB 与非 2 的幂次 12 KiB 均执行上述完整测试，通过；地址边界随容量变化 |
| 参数守卫 | 4 B、12 KiB、恰好结束在 CLINT 窗口之前三种配置启动通过；0、6 B、MMIO 重叠、32-bit 地址溢出四种配置按预期拒绝 |
| S1 兼容回归 | `b1-arbiter-test` PASS，仍为 10143 accepted / 10132 completed / 11 aborted，74 bins |

Xbar 的 12 个 reset 阶段为 idle、预留未接受、AR 已缓冲、AW-only、W-only、AW/W 已缓冲、下游 AW-only、下游 W-only、等待 R、等待 B、上游 R hold、上游 B hold。每次 reset 后重新运行读写事务。DECERR 独立测试覆盖预留、首通道接受、写收齐、响应持有等 15 个读写/顺序组合。

scripted slave 共记录 1872 次成功写事件（每个容量配置），包括 reset 前已经执行而未完成响应的写。该数字只用于检查转发/重复发送，不代表 SRAM 字节写、UART exactly-once 或真实设备副作用已验证。真实 DECERR 分支不计成功写事件。

覆盖计数来自实际握手、完成和停顿；必需 ordering、route/response、reset、strobe、stall、竞争 bin 在结束时检查。215/65 是功能 bin 数，不是代码覆盖率或完整 M3 cross coverage closure。当前没有无界 formal、四值仿真或系统级 master × route 验证。

## 3. 复现与证据

```bash
make -C npc b1-xbar-test b1-xbar-config-test

make -C npc b1-xbar-test B1_TEST_SRAM_BYTES=12288 \
  OBJ_DIR=/home/cym/prj/ysyx-workbench/npc/build/s2-cap12k

make -C npc b1-arbiter-test

verilator --lint-only --sv -Wall -DSYNTHESIS \
  --top-module axi4lite_xbar_test_top \
  npc/vsrc/bus/ysyx_axi4lite_xbar.sv \
  npc/vsrc/bus/ysyx_axi4lite_decerr.sv \
  npc/tests/axi4lite_xbar_test_top.sv
```

`b1-xbar-test` 自动先运行 lint 与 DECERR 独立测试。各自 CSV 位于相应 `OBJ_DIR/b1-{xbar,decerr}-test/coverage.csv`。参数检查入口为 [axi4lite_xbar_config_test.py](../../../../npc/tests/axi4lite_xbar_config_test.py)，结果在 `OBJ_DIR/b1-xbar-config-test/results.csv`；负例必须匹配预期的参数诊断及 abort，普通编译失败不能算拒绝成功。工具为 Verilator 5.008、G++ 11.4.0、GNU Make 4.3。

原始证据在 build 外的 `artifacts/m3-s2-20261014.tar.gz`，包含源码快照、实际命令、工具版本、失败/最终日志、CSV 和测试程序。摘要、源码及压缩包 SHA-256 见 [s2-manifest.json](s2-manifest.json)，当前仅本地归档。

实际遇到的问题与处理：

- ccache 的 `/run/user/1000/ccache-tmp` 在沙箱内不可写，获准沙箱外运行后通过。
- 直接把 Xbar 作为 Verilator 5.008 顶层时，数组端口被 SVA 采样后生成的 C++ 出现 `VlUnpacked` 与原生数组赋值错误；参数测试改用与功能测试相同的 wrapper，保留全部 SVA。
- 参数 0 以无尺寸十进制传入时触发 `WIDTHCONCAT`；参数脚本改用显式 32-bit 常量，未屏蔽该告警。
- 修正测试台一处 C++ 缩进告警，以及成功写统计误包含真实 DECERR 的问题；最终日志无新增编译告警。未观察到 RTL 功能 mismatch，不编造 RTL bug case。

## 4. 当前边界与下一步

S2 完成 T05/T06/T08 的 Xbar/default 子集及相关协议检查；[test-status.csv](test-status.csv) 仍保留 mapped slave 错误、实际设备副作用、双 master fabric 与 Core 系统验证为待完成。

本轮未连接 production filelist/Core，未改变 harness、AM 或 NEMU，未重跑无改动的 CPU/DiffTest。当前运行软件的 NPC 仍是 legacy 路径。M3 最终要求的代表波形和系统性能比较尚待集成/closure，不将本轮 CSV 当成完整 sign-off。

**无未解决阻塞。下一步 S3：实现 SRAM、UART、CLINT，验证字节写、非法操作无副作用、UART exactly-once、mtime rollover 与 reset。** 面试取舍已更新到 [qa/README.md](qa/README.md)。
