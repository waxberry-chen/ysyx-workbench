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
