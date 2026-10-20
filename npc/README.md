# NPC：M5 SoC 接口迁移

当前维护的硬件路径为 `ysyx_core → AXI4 adapter/arbiter → router/CLINT → ysyx_00000000`。
S1 已完成独立协议/CPU 回归及真实 SoC 静态展开；完整 ysyxSoC 仿真 harness、AM 和 DiffTest 分别在 S2/S3 接入。

```sh
make -C npc s1-test
# 按需单独运行：
make -C npc s1-protocol-test
make -C npc s1-cpu-test
make -C npc s1-elaboration-test
```

依赖 Verilator（支持 `--timing`）、C++17、Python3、`riscv64-linux-gnu-gcc/objcopy/nm`；
SoC 展开还需要先生成 `ysyxSoC/build/ysyxSoCFull.v`。运行产物在 `npc/build/m5-s1/`；
代表性波形为 `memory-1.fst`，commit 明细为 `memory-1.trace`。ISA 程序明细保留在 `npc/build/isa-contract-test/`。

- `filelist-soc.f` 是当前 CPU 子系统源闭包；`filelist.f` 仅列 core 与 adapters，不能直接配旧 C++ harness 运行。
- `NPC_PLATFORM=legacy/b1`、旧 `b1-*`/`axi4lite-*` 系统验收入口已停用；`build/run/sim` 在 S2 实现真实 SoC harness 后恢复。
- `filelist-b1.f`、B1 设备/fixture、`scripts/build.mk` 和旧 `csrc` 暂留作迁移参考，不属于当前可运行入口，不构成第二条兼容实现；历史运行使用 M4/S0 对应 Git revision。
- 旧 `ARCH=riscv32e-npc` 系统测试不再是当前运行入口。S1 直接使用 RV32E 定向程序和可控 AXI responder；完整 AM/SoC DiffTest 尚未验收。
- `flow/` 的 M4 Lite scope 已停用并给出明确诊断；已存在 run 仍可 inspect，历史基线用原 Git revision 复现。新 CPU scope/SDC 在 M5 S7 建立。

设计与测试迁移说明见 [M5 S1](../docs/notes/post-c/5-ysyx-soc-integration/1-axi4-interface.md)。
