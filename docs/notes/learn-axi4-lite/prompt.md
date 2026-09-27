请先阅读当前工程中与 IFU、LSU、memory interface 相关的 RTL (`npc/vsrc/`)，以及我提供的 AXI4 / AXI4-Lite specification (`docs/ref-spec/`)。

我目前对 AXI4-Lite 还比较陌生，希望采用“问题导向”的方式学习协议，而不是先从头阅读完整 specification，也不是进行掌握程度测试。

请结合当前源码和未来可能进行的 memory interface 改造，为我设计一组循序渐进的问题，引导我理解 AXI4-Lite 中真正重要的概念和细节。

每轮只给少量问题。我会带着这些问题阅读 specification，并用自己的话回答。

在我回答后，请：
- 判断我的理解是否准确；
- 指出遗漏、误解或表述不清的地方；
- 结合 specification 补充必要内容；
- 尽量结合当前源码中的具体 interface、signal 或 transaction 帮助我建立工程直觉；
- 将本轮问题的 feedback 写成文档放在 `docs/notes/learn-axi4-lite/` 下. 

问题可以涉及基础概念以及 handshake、read/write transaction、backpressure、channel independence、response、single outstanding、arbitration，以及后续 RTL 实现中可能遇到的 corner case。

目标是让我通过“问题 → 阅读 spec → 自己回答 → 反馈修正 → 下一轮问题”的循环逐渐建立对 AXI4-Lite 的完整理解。不要直接给答案，也不要修改代码。

## 轮次规划

本部分预计安排 8 轮问题，目标是能够独立设计和审查当前 NPC 的 AXI4-Lite 子系统，而不是穷尽完整 AMBA AXI 规范。

已完成：

1. 五通道职责、AXI4-Lite 相对完整 AXI 的简化，以及当前 NPC 接口差异；
2. `VALID/READY` 握手、backpressure、payload holding、reset 和组合路径；
3. `AR/R` 读事务、outstanding、IFU/LSU 映射和 adapter 边界。

后续规划：

4. **写事务**：`AW/W/B` 独立握手、任意先后、pending 状态、写响应依赖和事务完成边界；
5. **Adapter 实现细节**：request/response buffer、single-outstanding、byte lane、错误传播、reset，以及 fall-through/skid 的约束；
6. **Arbiter**：IFU/LSU 竞争、owner 保存、响应路由、读写关系、公平性、饥饿和 deadlock；
7. **Xbar 与 Slave**：地址译码、target 保存、default slave、`DECERR/SLVERR`、MMIO 副作用和 backpressure；
8. **结合 RTL 的综合审查**：用实际实现、波形和 assertions 检查 holding、outstanding、reset、组合路径、随机 stall 和错误路径，并梳理接入完整 AXI4 ysyxSoC 时的接口差异。

第 4、5 轮对应 AXI4-Lite adapter；第 6、7 轮对应后续 Arbiter/Xbar；第 8 轮在相关 RTL 完成后进行。若前序回答和实现已经充分覆盖，第 7、8 轮可以合并，因此预计还需 4～5 轮。
