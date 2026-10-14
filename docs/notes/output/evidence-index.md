# 工程事实与证据索引

> 更新：2026-10-14；实现快照：`5b6f29c`。这里只索引已有证据，不替代各阶段的测试与实验记录。

## 已有工程事实

| 可展示主题 | 实现入口 | 设计/实验依据 | 陈述边界 |
| --- | --- | --- | --- |
| 弹性前后端与事务控制 | [`npc/vsrc/core/`](../../../npc/vsrc/core/) | [架构导读](../post-c/1-memory-request/4-current-npc-architecture.md)、[开发记录](../post-c/1-memory-request/dev-log.md) | 架构导读是 Phase 2B 快照；精确访存异常等后续行为以开发记录和源码为准 |
| IFU/LSU AXI4-Lite adapters | [`npc/vsrc/bus/`](../../../npc/vsrc/bus/) | [IFU 记录](../post-c/2-axi4-lite/1-ifu-axi4-lite-adapter.md)、[LSU 记录](../post-c/2-axi4-lite/2-lsu-axi4-lite-adapter.md) | 各 single-outstanding；无 burst/AXI ID；外部窄 MMIO 读语义需在 SoC 接入前重新核对 |
| Core/仿真集成及异常回归 | [`npc/scripts/tests.mk`](../../../npc/scripts/tests.mk) | [集成记录](../post-c/2-axi4-lite/3-core-and-simulation-integration.md)、[阶段验收](../post-c/2-axi4-lite/4-signoff.md) | cause 1/4/5/6/7 定向测试；CPU tests 34/34，排除原 `unalign`；尚非完整 ISA compliance |
| 随机回压与软件 smoke | 同上 | [阶段验收 §2～3](../post-c/2-axi4-lite/4-signoff.md) | 随机回归为 `add`、seed 1～10、latency 7、ready 50%；RTC/yield-os 为预期 timeout smoke |
| 架构一致性与性能样本 | commit trace / simulation statistics | [基线](../post-c/2-axi4-lite/0-freeze-baseline.md)、[验收 §4、§6](../post-c/2-axi4-lite/4-signoff.md) | 固定 `add` 样本：1095 commits，5121 → 7801 cycles；架构字段 hash 一致。不是通用性能结论或 PPA 优化成果 |

已有 AXI 阶段验收的 RTL 基线为 `94cf9ac`，验收提交为 `5b6f29c`。复现入口：

```bash
make -C npc axi4lite-signoff
```

具体构建依赖和参数以阶段记录及脚本为准；本次文档整理未重新运行回归。既有日志位于可清理的 `npc/build/`，这里不保证其仍然保留；引用新数据时应按 roadmap 保存可定位的报告归档。

## 尚未形成的证据

- RTL Arbiter/Xbar/slaves 与 ysyxSoC 启动/中断闭环。
- DC 映射综合、PrimeTime STA、面积/关键路径/时序结果。
- 明确条件下的架构优化对照实验、功耗分析或 PnR 结果。
- machine-readable functional coverage closure 与 bounded formal 结果。

上述内容只列为计划，不写成已完成的简历成果。后续阶段产生证据后补一行索引，无须预先制作空报告。

## 最小维护方式

1. 开发事实、设计取舍、bug 和实验条件写入所属阶段；本页只链接可用于展示的结果。
2. 重要功能或优化验收后，更新本页和项目简介；小提交不要求逐次编写展示文档。
3. 对外使用某项结论前，检查实现版本、个人贡献、验证范围与已知限制，并选择一张图、一组数据或一个 bug case 支撑它。
