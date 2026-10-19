# M5 开发日志

## 2026-10-19：建立计划

- 输入：M4 已验收；本地 HEAD `d7c5b139eca8f6ffc467ecea472d4395998b1cea`。阅读 roadmap、M4 交接、原版 2607 C5/2306 B2、本地重组讲义及现有 core/AM/harness/RT-Thread 实现。
- 建立 [S0–S8 计划](plan.md)与 [M01–M18 验收矩阵](test-plan.md)，未执行 SoC 集成或修改源码。
- 关键决定：保留 B1 Lite；从 local req/rsp 边界引入保留 byte address/size 的原生 AXI4 单拍路径；CPU 内部 CLINT 与 timer interrupt 分步实现；Flash → SRAM 先证明启动，PSRAM 按真实容量纳入。
- 发现现有 RT-Thread 两线程静态栈合计 16 KiB，另有 heap > 32 KiB 断言，不适合讲义中的 8 KiB SRAM；S0 需固定容量路线，不能直接复制 B1 的 1 MiB SRAM 配置。
- 发现现有 MMIO 标记按 `0xa...` 地址判断，必须随新平台修改，否则 UART 与未来 SDRAM 的 DiffTest 分类错误。AM 中断开关当前为空实现，协作 RT-Thread 不构成中断验收证据。
- 当前无计划编写阻塞；实施前置为上游 revision/依赖生成、模型缺口审查、reset/IRQ/容量契约。在线 `ysyx6` 仅作调研线索，尚未固定或生成。
- 下一步：S0。完成后新增真实 `0-upstream-contract.md` 和验证记录；不预先创建 signoff 或填写 PASS。

## 2026-10-19：S0 完成，上游与平台契约冻结

- 输入主仓库 `30bc679`，ysyxSoC `df38a4d...`，分支 `npc-integration`；用户已安装工具、初始化依赖并生成。本次重新执行 `make -B -C ysyxSoC verilog` 成功，Rocket Chip实际diff与上游补丁一致。
- 新增 [实际契约](0-upstream-contract.md)、[检查脚本](../../../../npc/tests/ysyx_soc_contract_check.py)及精选 [manifest](s0-validation/manifest.json)。上游spec与生成实例61个端口一致；真实外围源加空CPU的静态展开通过，242条告警分类保留；没有NPC运行/完整SoC lint clean结论。
- 冻结仿真top为`ysyxSoCFull`、CPU占位名`ysyx_00000000`、关闭ChipLink/FAST_FLASH、SDRAM走APB但不使用；CPU外部IRQ固定0。reset经10级移位链，初始共同reset约定至少20个上升沿；默认仿真100MHz，不与S7的200MHz约束混淆。
- 核对真实地址：SRAM8KiB、MROM4KiB、PSRAM4MiB；现有RTT ELF静态段42,932B，确定S4接通PSRAM。Flash backing限制16MiB，PSRAM颗粒模型及真实XIP需实现。
- 发现原上游不能保证所有非法地址均返回DECERR，MROM写会断言，空外设有未驱动输出；已分配S2处理。另有DPI backing、旧MMIO分类、带延时外围仿真配置，以及S5的AM/RTT中断链缺口。
- M01/M02 的S0范围通过；没有当前外部阻塞，下一步S1。未修改NPC/SoC功能RTL，保留用户`.gitignore`修改与预期Rocket Chip补丁，未git add/commit。
