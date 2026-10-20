# NPC：M5 SoC 接口迁移

当前维护的硬件路径为 `ysyx_core → AXI4 adapter/arbiter → router/CLINT → ysyx_25030087`。
S2 已完成真实 `ysyxSoCFull` harness、MROM/UART/SRAM 定向运行与错误传播；AM 和 DiffTest 在下一步 S3 接入。

```sh
make -C npc s2-test
make -C npc run IMG="$PWD/npc/build/m5-s2/uart.bin" \
  ARGS="--trace build/m5-s2/uart.fst --uart-log build/m5-s2/uart.tx"
make -C npc s1-test
# 按需单独运行：
make -C npc s1-protocol-test
make -C npc s1-cpu-test
make -C npc s1-elaboration-test
```

依赖 Verilator（支持 `--timing`）、C++17、Python3、`riscv64-linux-gnu-gcc/objcopy/nm`；
SoC 构建还需要 S0 的 Java/Mill/firtool 环境；`build/run/s2-test` 自动检查并生成 `ysyxSoC/build/ysyxSoCFull.v`。运行产物在 `npc/build/m5-s1/`；
代表性波形为 `memory-1.fst`，commit 明细为 `memory-1.trace`。ISA 程序明细保留在 `npc/build/isa-contract-test/`。

- `filelist-soc.f` 是当前 CPU 子系统源闭包；`filelist.f` 仅列 core 与 adapters，不能直接配旧 C++ harness 运行。
- `NPC_PLATFORM=legacy/b1`、旧 `b1-*`/`axi4lite-*` 系统验收入口已停用；`build/run/sim` 当前运行真实 SoC，IMG 是最多 4 KiB 的 MROM raw binary。
- `filelist-b1.f`、B1 设备/fixture、`scripts/build.mk` 和旧 `csrc` 暂留作迁移参考，不属于当前可运行入口，不构成第二条兼容实现；历史运行使用 M4/S0 对应 Git revision。
- 旧 `ARCH=riscv32e-npc` 系统测试不再是当前运行入口。S1 直接使用 RV32E 定向程序和可控 AXI responder；完整 AM/SoC DiffTest 尚未验收。
- `flow/` 的 M4 Lite scope 已停用并给出明确诊断；已存在 run 仍可 inspect，历史基线用原 Git revision 复现。新 CPU scope/SDC 在 M5 S7 建立。

设计与测试迁移说明见 [M5 S1](../docs/notes/post-c/5-ysyx-soc-integration/1-axi4-interface.md)。

S2 产物位于 `npc/build/ysyxsoc/` 和 `npc/build/m5-s2/`；harness 不预加载 SRAM。默认100 MHz、UART接收器8N1/每bit16周期；波特率变化时设置 `--uart-bit-cycles`。详细运行、错误策略与证据见 [M5 S2](../docs/notes/post-c/5-ysyx-soc-integration/2-bringup.md)。
