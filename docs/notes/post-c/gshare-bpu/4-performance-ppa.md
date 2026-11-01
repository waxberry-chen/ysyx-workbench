# S4：三模式性能与 DC/PT 对照

> 2026-11-01；S4 完成。固定六程序性能与 OFF/GSHARE 同条件 DC/PT 对照通过；面积增加 21.076%，两组均满足 5 ns 数据时序与电气要求。沿用 leakage 零目标例外与 reset 物理时序 deferred，功耗未验收。完整审查及原始证据见 [PPA 归档](validation/ppa/README.md)。

**加速比**：基准 cycles / 当前 cycles，大于 1 表示更快。**CPI**：cycles / 提交指令数。本页测的是固定频率下仿真周期差异；若新硬件未满足原 5 ns 时钟，不能直接宣称同等墙钟时间收益。没有用 28 nm 的经验频率代替本轮 STA。

## 1. 同输入三模式结果

运行 [bpu_performance.py](../../../../npc/tests/bpu_performance.py)，18 次均通过全程 DiffTest 及终态 SRAM/PSRAM 比较。六个 `.bin` hash 与 M5 冻结清单一致，跨模式完整提交序列一致；OFF cycles/commits 与历史基线一致。所有程序冷启动，包含启动代码，无 AXI 随机 delay。

| 程序 | OFF cycles | JAL_ONLY cycles | GSHARE cycles | OFF / GSHARE | JAL_ONLY / GSHARE | GSHARE 方向准确率 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| micro-sieve | 186362 | 185933 | 155214 | 1.201× | 1.198× | 95.91% |
| micro-fib | 1633239 | 1626375 | 1446962 | 1.129× | 1.124× | 74.85% |
| cpu-if-else | 489253 | 421484 | 420900 | 1.162× | 1.001× | 94.58% |
| cpu-recursion | 1620552 | 1472988 | 1454154 | 1.114× | 1.013× | 81.75% |
| cpu-bubble-sort | 842230 | 762442 | 727183 | 1.158× | 1.048× | 84.60% |
| cpu-quick-sort | 1558810 | 1369507 | 1353374 | 1.152× | 1.012× | 91.24% |

结论只覆盖这六个固定镜像：总增量改善 1.114～1.201×，纯条件分支预测在共同 JAL/恢复框架之上的改善差异很大。`if-else` 的大部分改善来自 JAL 提前处理，不能把 1.162× 全部称为 GShare 的贡献；`sieve` 的 1.198× 条件分支增量则明显。未做表规模／历史长度扫参，不声称这个配置最优。

| 程序 | commits | OFF CPI | JAL_ONLY CPI | GSHARE CPI | 合法 branch 数 | GSHARE 方向错误 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| micro-sieve | 9688 | 19.236 | 19.192 | 16.021 | 2666 | 109 |
| micro-fib | 94717 | 17.243 | 17.171 | 15.277 | 28901 | 7270 |
| cpu-if-else | 1521 | 321.665 | 277.110 | 276.726 | 295 | 16 |
| cpu-recursion | 9030 | 179.463 | 163.122 | 161.036 | 1666 | 304 |
| cpu-bubble-sort | 4154 | 202.752 | 183.544 | 175.056 | 1175 | 181 |
| cpu-quick-sort | 6416 | 242.957 | 213.452 | 210.937 | 1370 | 120 |

## 2. 恢复事件解释

| 程序 | B 恢复 | JAL 恢复 | JALR 恢复 | 丢弃响应 | 被清 IFQ 条目 | 恢复平均周期 / 最大周期 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| micro-sieve | 109 | 0 | 14 | 123 | 0 | 25.00 / 25 |
| micro-fib | 7270 | 0 | 482 | 7752 | 0 | 24.88 / 25 |
| cpu-if-else | 16 | 0 | 17 | 33 | 0 | 206.09 / 593 |
| cpu-recursion | 304 | 0 | 379 | 683 | 0 | 147.36 / 593 |
| cpu-bubble-sort | 181 | 0 | 46 | 227 | 0 | 153.19 / 593 |
| cpu-quick-sort | 120 | 0 | 78 | 198 | 0 | 154.09 / 593 |

表中为 GSHARE。六项的 branch 查询覆盖率均为 100%，训练数等于正常提交条件分支数，未分类 redirect 为零；从 commit trace 的 opcode/exception 位独立统计的分支数也与 monitor 分母一致，见 [trace 检查](validation/trace-branch-counts.json)。方向错误与 NPC 错误在这六个程序中恰好相等，但 offset=4 的局部测试已验证二者可不同。

JAL 不再造成恢复，JALR 的函数返回／间接跳转恢复仍存在。IFQ 被清条目数为零是这一批真实延迟、单 outstanding 程序的实测形态，不能据此删除 flush：错误取指主要处于已发请求／响应排空阶段。IFU 随机单元覆盖了队列里有上下文时的恢复。Flash/PSRAM 程序仍受串行存储延迟影响，恢复最大值达 593 拍，不能把所有错误按固定“两拍罚时”估算。

## 3. 服务器面积／时序对照

两组已回传，配置区别只在 `NPC_BPU_MODE`，沿用同一源码 filelist、`soc_cpu.sdc`、TT DB、5 ns、Ultra、max fanout 32、cap90、可选功耗报告关闭和 reset 物理时序 deferred；Ultra 自带的 leakage 优化仍自动启用：

- [npc_soc_cpu_bpu_off.tcl](../../../../npc/flow/00_indata/configs/npc_soc_cpu_bpu_off.tcl)
- [npc_soc_cpu_bpu_gshare.tcl](../../../../npc/flow/00_indata/configs/npc_soc_cpu_bpu_gshare.tcl)

原 `npc_soc_cpu.tcl` 现在也显式选择模式 2；旧 M5 复现必须使用冻结源码，不把当前同名配置当成 M5 RTL。flow driver 只允许三种审查过的宏组合，拒绝缺模式、重复模式、非法值和 simulation 宏；实际模式进入 manifest、run.tcl 和 scope 描述。新增回归验证这种快照行为。本地检查验证的是源闭包／SDC 契约／driver，不等于 DC/PT PASS。

本次服务器输入为 `9d7c63d`，使用以下命令；以后复现请使用新的 RUN_ID，SITE 路径按服务器实际位置替换：

```bash
make -C npc/flow all CONFIG=00_indata/configs/npc_soc_cpu_bpu_off.tcl \
  SITE=00_indata/configs/site.local.tcl RUN_ID=soc-cpu-tt-5ns-bpu-off
make -C npc/flow all CONFIG=00_indata/configs/npc_soc_cpu_bpu_gshare.tcl \
  SITE=00_indata/configs/site.local.tcl RUN_ID=soc-cpu-tt-5ns-bpu-gshare
```

重点比较新增 PHT、IFQ metadata、目标加法／选择和恢复比较的真实面积，以及 setup/hold、DRC、coverage、告警。不要改变约束来获得可比性表面通过；同一份 site/库必须用于两个 run。功耗仍不在验收范围。

### 3.1 回传实测与审查结论

| 指标 | OFF | GSHARE |
| --- | ---: | ---: |
| Cell area（library_area） | 9583.727856 | 11603.591918 |
| 触发器数 | 1623 | 2006 |
| 全局最差 setup slack（ns） | +2.444726 | +1.801808 |
| Reg2Reg 最差 setup slack（ns） | +2.591039 | +1.801808 |
| 全局最差 hold slack（ns） | +0.009693 | +0.008700 |
| PT 约束违例 | 0 | 0 |
| setup / hold coverage | 各 1623 项，100% met | 各 3304 项，100% met |

新增面积为 **2019.864062 library_area（+21.076%）**。实际网表保留 256 个 PHT 位和 7 个 GHR 位，预测器模块面积 1518.2160；其余成本包含 predecode、metadata、恢复逻辑及重新映射。这里是完整 OFF→GSHARE 的代价，未做 JAL_ONLY 综合，不能单独给出纯方向预测的面积增量。

两组各 98 个登记输入/产物 hash 均匹配，RTL、SDC、脚本及记录的外部库/工具 hash 一致，配置仅模式不同；没有放宽约束。DC/PT 进程正常完成，主日志和报告无 Error/Fatal。原始 DC `CONSTRAINT_FAIL` 仅为已接受的 leakage 零目标；PT `REVIEW_REQUIRED` 的 9120 / 13534 项 untested 全部归入 reset/set 时序 deferred 或 81 个常量输出的 setup/hold 检查，无未解释项。

GSHARE 全局 setup 路径为 opbuf `alu_ctrl[0]` → ALU → EXU/恢复控制 → IFU/IFQ → decoder → opbuf `csr_wen`。最差路径未经过 PHT 查询，但新增方案已降低整体时序余量。两组均通过 200 MHz pre-layout 目标；不将正裕量反推物理 Fmax。8.7 ps 的最差 hold 裕量不代表 CTS 后通过。

**无新增验收阻塞，S4 在约定范围内通过；S5 已复用本页证据完成[最终冻结与交接](signoff.md)。** 原始自动状态、coverage 逐项处置、告警及关键路径详见 [审查记录](validation/ppa/README.md)。功能/性能 harness 仍使用 100 MHz；周期比较与 200 MHz STA 是不同测量，未新增 200 MHz 整机运行。六程序的速度提升均小于 21.076% 面积增幅，因此应表达为性能/面积取舍，不宣称同频 throughput/area 或能效改善。

## 4. 复现与原始证据

```bash
make -C npc bpu-performance
```

该入口构建三模式的 MROM/Flash 仿真器，沿用固定二进制输入并生成 18 份 summary/trace。完整数据在 `npc/build/gshare-bpu/performance/`；精选归档见 [validation/README.md](validation/README.md)。CPI、加速比和上述事件都能由 JSON 直接复算。
