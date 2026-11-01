# GShare 增量状态与交接

> 2026-11-01；**S0–S5 在约定范围内全部完成，GShare 增量验收并冻结，无未处置阻塞。** 下一项为 JOB-PREP-01：理解考察与简历 v1。

| 步骤 | 当前状态 | 阅读入口 |
| --- | --- | --- |
| S0 接口／输入基线 | 完成；六程序 OFF 与 M5 一致 | [合同与指标](0-contract-and-metrics.md) |
| S1 预测器单元 | 完成；预译码、两种表参数、PHT/GHR 独立模型 | [预测器](1-predictor.md) |
| S2 前端与恢复 | 完成；IFU scoreboard、EXU 定向及两项检查器负例 | [集成闭环](2-integration.md) |
| S3 系统功能 | 完成；新增定向及 M5 S3～S6 全部适用回归通过 | [功能验证](3-functional-validation.md) |
| S4 性能／面积时序 | 完成；18 次性能比较及同条件 OFF/GSHARE DC/PT 审查通过，保留 leakage/reset 例外 | [性能与 PPA](4-performance-ppa.md) |
| S5 最终冻结 | 完成；源码/归档身份核对、单次最小复现、文档与求职准备交接 | [冻结核对](validation/freeze-check.json)、下文 S5 记录 |

当前实现是 GShare + predecode，支持合法条件分支和 JAL 的提前取指；JALR 保留执行端恢复。冻结默认为模式 2（GSHARE），保留模式 0（OFF）和模式 1（JAL_ONLY）对照；PHT 为 128 × 2-bit，7-bit 提交历史，索引为 PC[8:2] XOR GHR。未加入 BTB、RAS、cache、多 outstanding 或新的软件平台。

性能结论：固定六程序整体 OFF/GSHARE=1.114～1.201×；条件分支部分须看 JAL_ONLY/GSHARE=1.001～1.198×，不能混淆 JAL 提前处理与 GShare 的贡献。CPU 子系统 cell area 从 9583.727856 增至 11603.591918 library_area（+21.076%）；两组满足 5 ns，GSHARE 最差 setup/hold slack 为 +1.801808/+0.008700 ns。未测物理最高频率或功耗，不宣称面积效率提升。

本地证据：复用系统回归 146 次真实 SoC 正向运行、3,372,127 条差分提交、47 次 IRQ；新增 12 次错误路径／IRQ 对照、18 次三模式性能运行通过。原有 26 项预期失败检查及新增 2 项检查器负例通过；12 组 scope profile、57 项 flow mock 检查通过。完整统计见 [S3](3-functional-validation.md)及 [validation](validation/README.md)。

服务器审查输入固定为 `9d7c63d562c2298e7f00451eab37c946205733e8`；每组 98 个登记输入/产物 hash 匹配，源码与功能测量交接版本一致。DC 仅剩已接受的 leakage 零目标，PT 无约束违例；全部 untested 已按 reset/set deferred 和常量输出处置。原始状态及证据见 [PPA 审查](validation/ppa/README.md)。

## S5：冻结版本与证据复用

主仓库冻结入口为 **`4dbccf6ebe9d34bc9dea2e8a1b89fa1a19cac39f`**。这是已有实现和 S4 审查材料的提交；本次 S5 只补充文档与小型核对结果，不修改 RTL、harness、软件或 flow。服务器测量输入仍记录为 `9d7c63d`，不把文档提交写成重新测量的版本。

| 冻结组成 | 版本／已有依据 | 本轮核对 |
| --- | --- | --- |
| RTL、harness、AM/NEMU 与测试源文件 | [handoff-source.json](validation/handoff-source.json) | 135 个文件全部匹配；原测量后的注释尾空格变化继续由原 formatting 记录解释 |
| ysyxSoC / RocketChip | `2d365297` / `d0c6b50f` + [M5 已归档补丁](../5-ysyx-soc-integration/s8-validation/patches/ysyxSoC__rocket-chip.patch) | 当前唯一嵌套仓库改动与该补丁逐字节一致；它把 AXI lock/cache/prot/qos 字段宽度设为 0，属于已有生成接口配置 |
| 外部软件依赖 | am-kernels `9804c830`、rt-thread-am `bce7f1d5` | HEAD 与既有依赖一致，工作区干净；完整 SHA 见冻结核对 JSON |
| 六程序比较输入 | [M5 comparison-inputs.json](../5-ysyx-soc-integration/s8-validation/comparison-inputs.json) | 6 个 BIN + 6 个 ELF hash 全部匹配，沿用原镜像 |
| OFF/GSHARE DC/PT | [原 PPA 归档](validation/ppa/README.md)及 [archive.json](validation/ppa/archive.json) | 194 份原始文本的大小与 hash 全部匹配；不复制第二套报告，不改写自动状态 |

因此，本冻结版本是**主仓库提交 + 固定外部依赖 + 已有 RocketChip 补丁**。单独 checkout 主仓库 SHA 并不能替代补丁及本地比较镜像；恢复依赖的方法沿用 [M5 S8 交接](../5-ysyx-soc-integration/8-reproduction-handoff.md)。当前工作区已应用该补丁，保留现状，不重复 apply，也不为 S5 修改子模块提交。

本轮仅重新运行 **1 次 GSHARE micro-sieve**，用于确认现有复现入口仍可用。运行前确认 DUT 可执行文件、NEMU reference 和 BIN 的 hash 均与 [performance.json](validation/performance.json) 的 `2-micro-sieve` 相同；运行后完整 summary 与 commit trace hash 均与原测量一致：**155214 cycles、9688 commits，9688 条全部 DiffTest，2666 次分支训练、109 次方向错误**。SRAM/PSRAM 终态检查通过。此次是复现原样本，不增加独立 workload 或覆盖率计数。

源码未变，已有 S1–S4 功能/性能/EDA 证据继续有效，因此未重跑系统全量、三模式 18 次性能比较、SoC 干净构建或 DC/PT。这里只新增 [freeze-check.json](validation/freeze-check.json) 保存核对结果；临时 smoke 日志/trace 留在 `/tmp`，原测量和历史失败材料保持原样。

## 复现与阅读入口

在仓库根目录、既有二进制与冻结镜像仍可用时，最小入口如下；检查 summary 的 `pass=true`、`bpu.mode=2`、上述周期/提交数，trace hash 应为 `performance.json` 中的原值：

```bash
npc/build/ysyxsoc/VysyxSoCFull \
  --mrom artifacts/m5-s8-20261030/comparison/micro-sieve/micro-sieve-riscv32e-ysyxsoc.bin \
  --diff nemu/build/ysyxsoc/nemu-ref.so --max-cycles 300000000 \
  --summary /tmp/npc-gshare-s5.json --uart-log /tmp/npc-gshare-s5.uart \
  --commit-trace /tmp/npc-gshare-s5.csv
```

二进制缺失时，先按 M5 环境准备依赖，再执行 `make -C npc soc-ref` 和 `make -C npc soc-build SOC_BOOT=mrom BPU_MODE=2`；此时是在重新构建，不能预设可执行文件 hash 不变。固定性能镜像在本地 `artifacts/`，不随 Git 分发；缺失时按原清单恢复，不能用临时重新编译的镜像冒充原比较输入。单元、完整系统及三模式性能入口沿用 [validation README](validation/README.md)，DC/PT 命令沿用 [S4](4-performance-ppa.md#3-服务器面积时序对照)，按变更影响选择运行。

按 [S1 预测器](1-predictor.md) → [S2 闭环图与源码](2-integration.md) → [S3 测试](3-functional-validation.md) → [S4 性能/面积/时序](4-performance-ppa.md) → [QA](qa/README.md) 阅读。S5 核对了图中的预测、元数据、提交训练与恢复路径，补明确 IRQ 优先恢复和 IFQ 清理箭头；QA 已包含收益归因、面积代价和 coverage 解释，复用原材料。展示用 Core/SoC/验证三张图的进一步整理留给求职复盘。

## 遗留范围与下一步

既有边界继续保留：instruction-address-misaligned trap 未在 M5 完整实现，本轮仅禁止对半字对齐目标提前预测；reset 物理时序、完整 SoC PnR 和功耗签核仍不在本轮范围。局部与系统验证不能据此宣称全 ISA 或物理 sign-off。

下一步为 **[JOB-PREP-01：理解考察与简历 v1](../../output/interview-readiness.md)**。工程验收已完成，个人理解考察仍待实际开展；不自动继续扩展 BTB/cache 或增加新的冻结前置。
