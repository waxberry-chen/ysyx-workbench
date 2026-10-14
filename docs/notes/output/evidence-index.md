# 工程事实与证据索引

> 更新：2026-10-14；Core/adapters 验收快照：`5b6f29c`；M3 候选源码见阶段 manifest。这里只索引已有证据，不替代各阶段的测试与实验记录。

## 已有工程事实

| 可展示主题 | 实现入口 | 设计/实验依据 | 陈述边界 |
| --- | --- | --- | --- |
| 弹性前后端与事务控制 | [`npc/vsrc/core/`](../../../npc/vsrc/core/) | [架构导读](../post-c/1-memory-request/4-current-npc-architecture.md)、[开发记录](../post-c/1-memory-request/dev-log.md) | 架构导读是 Phase 2B 快照；精确访存异常等后续行为以开发记录和源码为准 |
| IFU/LSU AXI4-Lite adapters | [`npc/vsrc/bus/`](../../../npc/vsrc/bus/) | [IFU 记录](../post-c/2-axi4-lite/1-ifu-axi4-lite-adapter.md)、[LSU 记录](../post-c/2-axi4-lite/2-lsu-axi4-lite-adapter.md) | 各 single-outstanding；无 burst/AXI ID；外部窄 MMIO 读语义需在 SoC 接入前重新核对 |
| AXI4-Lite Arbiter、Xbar/default | [`npc/vsrc/bus/`](../../../npc/vsrc/bus/) | [S1](../post-c/3-axi4-lite-interconnect/1-arbiter.md)、[S2](../post-c/3-axi4-lite-interconnect/2-xbar.md)、[Q&A](../post-c/3-axi4-lite-interconnect/qa/README.md) | 模块与 Core/B1 集成通过；完整 fabric 随机/交叉覆盖仍待 S5 |
| RTL SRAM/UART/CLINT | [`npc/vsrc/periph/`](../../../npc/vsrc/periph/) | [S3 设备报告](../post-c/3-axi4-lite-interconnect/3-slaves.md)、[manifest](../post-c/3-axi4-lite-interconnect/s3-manifest.json) | 三种容量模块测试通过；Core/AM 集成见 S4；尚无 SRAM macro/PPA 证据 |
| Core/仿真集成及异常回归 | [`npc/scripts/tests.mk`](../../../npc/scripts/tests.mk) | [集成记录](../post-c/2-axi4-lite/3-core-and-simulation-integration.md)、[阶段验收](../post-c/2-axi4-lite/4-signoff.md) | cause 1/4/5/6/7 定向测试；CPU tests 34/34，排除原 `unalign`；尚非完整 ISA compliance |
| 随机回压与软件 smoke | 同上 | [阶段验收 §2～3](../post-c/2-axi4-lite/4-signoff.md) | 随机回归为 `add`、seed 1～10、latency 7、ready 50%；RTC/yield-os 为预期 timeout smoke |
| 架构一致性与性能样本 | commit trace / simulation statistics | [基线](../post-c/2-axi4-lite/0-freeze-baseline.md)、[验收 §4、§6](../post-c/2-axi4-lite/4-signoff.md) | 固定 `add` 样本：1095 commits，5121 → 7801 cycles；架构字段 hash 一致。不是通用性能结论或 PPA 优化成果 |
| B1 系统集成 | [`npc/vsrc/top/`](../../../npc/vsrc/top/)、[`系统测试`](../../../npc/tests/b1_system_test.py) | [S4 报告](../post-c/3-axi4-lite-interconnect/4-integration.md)、[manifest](../post-c/3-axi4-lite-interconnect/s4-manifest.json) | 53 个固定时序系统程序、第二配置 3 个 AM 程序、legacy 兼容通过；含真实 stale DECERR、构建 VPATH bug case；RT-Thread/完整覆盖待 S5 |

已有 AXI 阶段验收的 RTL 基线为 `94cf9ac`，验收提交为 `5b6f29c`。复现入口：

```bash
make -C npc axi4lite-signoff
```

具体构建依赖和参数以阶段记录及脚本为准。S4 已实际重跑相关系统/legacy 用例，并将源码、镜像和日志保存到 build 外的本地归档；更早阶段的 build 日志仍可能被清理。B1 复现入口为 `make -C npc b1-system-test`。

## 尚未形成的证据

- 完整 fabric 随机/交叉覆盖与 RT-Thread closure，以及 ysyxSoC 启动/中断闭环。
- DC 映射综合、PrimeTime STA、面积/关键路径/时序结果。
- 明确条件下的架构优化对照实验、功耗分析或 PnR 结果。
- machine-readable functional coverage closure 与 bounded formal 结果。

上述内容只列为计划，不写成已完成的简历成果。后续阶段产生证据后补一行索引，无须预先制作空报告。

## 最小维护方式

1. 开发事实、设计取舍、bug 和实验条件写入所属阶段；本页只链接可用于展示的结果。
2. 重要功能或优化验收后，更新本页和项目简介；小提交不要求逐次编写展示文档。
3. 对外使用某项结论前，检查实现版本、个人贡献、验证范围与已知限制，并选择一张图、一组数据或一个 bug case 支撑它。
