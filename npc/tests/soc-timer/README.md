# M5 S5 timer tests

入口为 `make -C npc s5-test`，产物在 `npc/build/m5-s5/`。
设计、源码阅读和验证分层见 [S5](../../../docs/notes/post-c/5-ysyx-soc-integration/5-timer-interrupt.md)。

| 文件 | 用途 |
| --- | --- |
| `trap.S` | 手写 cause/EPC 自检、独立 MIE/MTIE 屏蔽、只读 MTIP、MRET 后仍 pending、未知 CSR |
| `timer-registers.c` | 软件写 mtime 制造低位溢出、稳定读取、64-bit compare 重装与 MTIP 清除 |
| `am-timer.c` / `registers.S` | AM 中断事件、真实开关、四次 timer IRQ、上下文哨兵；三种启动布局 |
| `latency.S` | 随机总线背压/响应等待期间的 IRQ；200 次 store/load，程序、提交与物理计数核对 |
| `rtthread-tick.c` | 单线程 kernel tick、临界区嵌套和 IRQ nest 检查；完整抢占/阻塞验收留 S6 |
| `rtthread-bsp.patch` | 独立 RT-Thread checkout 的两个 BSP 文件修改，供主仓库重放 |

RT-Thread 的基础 revision 为 `beb7fa16e7d282c9409cfbb78225249d193e276e`。
`rt-thread-am/` 在主仓库被忽略，且不是 submodule；本轮修改仍在其自身工作区，不能只提交主仓库后假定它已被 Git 记录。主仓库中的补丁提供复现路径。

首次在该基础 revision 上准备环境：

```bash
git -C rt-thread-am apply --check ../npc/tests/soc-timer/rtthread-bsp.patch
git -C rt-thread-am apply ../npc/tests/soc-timer/rtthread-bsp.patch
make -C npc s5-test
```

已应用后不要重复 apply，可以用 `git apply --reverse --check` 检查补丁处于已应用状态。若本地还改过相同 BSP，应先审查冲突；测试只核对，不修改依赖仓库。

`irq-epc-negative` 会故意破坏取样 EPC，让差分报错；`context-negative` 会复制镜像并将恢复 t0 的指令改成 NOP，让寄存器自检失败。它们预期非零退出，脚本核对诊断内容后才计为负例 PASS。
