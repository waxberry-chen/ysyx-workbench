# M4 综合结果记录

按实验顺序保存首次综合、基线准备、正式基线和后续优化结果。失败或未达标结果同样保留，不用新结果覆盖旧报告。编号是实验记录编号，不是 milestone/stage 编号；正式 S3 基线建立后在此明确标记。

| 记录 | 日期 / run | 定位与结论 |
| --- | --- | --- |
| [01 首次综合](01-first-synthesis/README.md) | 2026-10-17 / `core-tt-10ns-split` | DC 完成；10 ns setup/hold 未满足；PT 未运行；用于发现实现/评估问题，不作为正式 S3 基线 |
| [02 RV32E / 无 M](02-rv32e-no-m/README.md) | 2026-10-18 / `core-tt-10ns-rv32e-nom` | DC/PT 完成，10 ns 无 setup/hold 违例；面积 9511.319905；PT 有 66 条 min-capacitance 违例、5516 项脉宽检查未测试，正 slack 路径未输出；仍非正式基线 |
| [03 200 MHz 候选](03-200mhz-candidate/README.md) | 2026-10-18 / `core-tt-5ns-baseline` | DC/PT 完成；PT setup/hold slack +0.531597/+0.013534 ns；面积不变；高扇出确认为 clk，禁用弧无 loop-breaking 标记；66 条 min-capacitance 和复位脉宽审查仍未关闭，尚非正式基线 |
| [04 200 MHz 基线](04-200mhz-baseline/README.md) | 2026-10-18 / `core-tt-5ns-no-port-buffers`，HEAD `9e449fac` | **S3 范围内基线成立**；DC/PT 无约束违例；setup/hold +0.596843/+0.008754 ns；面积 9242.855942；9426 reset deferred + 24 常量条件禁用已分类；独立复现见 05 |
| [05 S6 独立复现](05-s6-reproduction/README.md) | 2026-10-19 / `core-tt-5ns-s6-repro`，HEAD `9e449fac` | **S6 / 本轮 M4 验收完成**；面积、时序、coverage、负载和告警复现 04；网表/SDC 仅日期注释不同，43 份报告仅日期与四行耗时不同；范围限制不变 |

每次有价值的综合实验建立独立目录，记录设计范围、实际源版本及 dirty 状态、工具/库/约束/互连模型、指标、关键路径、问题和下一步。记录布局：

- `README.md`：分析与结论，区分执行完成、时序通过、正式基线资格。
- `reports/`、`logs/`：有助于解释结果的原始文件，逐字节保留，不修改格式或移除失败数据。
- `provenance/`：原始 manifest、实际配置/约束与必要的版本追溯信息。
- `archive.json`：归档文件到原 run 文件的映射、大小和 SHA-256，保证 clean run 后仍能核对证据。

日常临时 run 仍在 `npc/flow/build/`；准备 clean 或发布结论前，将需要长期保留的实验纳入本索引。这里是审阅归档，不是可直接继续执行的 run：完整网表/DDC/RTL 快照和服务器工具/库仍按原 run 管理，原 manifest 不重写绝对路径。工艺 DB/完整库报告不纳入本次归档。

正式基线前允许有目的地纠正观察接口、算术实现和约束问题，但每项变化都要明确原因并重新验证。工艺节点不能单独决定可达频率；不能通过屏蔽慢路径、遗漏端口约束或只留下较好结果来建立基线。改变观察范围、M 运算延迟、GPR 数量或互连模型后必须注明比较边界。
