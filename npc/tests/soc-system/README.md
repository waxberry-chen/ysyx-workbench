# M5 S6 system tests

Build and run all groups with `make -C npc s6-test`. Products stay under
`npc/build/m5-s6/`; the normal and delayed SoC executables have separate build
directories. Prepare the fixed RT-Thread checkout/BSP as described in
[S5's fixture README](../soc-timer/README.md).

After `make -C npc s6-build s6-delay-test`, run a focused group:

```bash
python3 npc/tests/m5_s6_test.py --only rtthread
python3 npc/tests/m5_s6_test.py --only uart
python3 npc/tests/m5_s6_test.py --only random
python3 npc/tests/m5_s6_test.py --only regression
```

Each group saves its own `manifest-*.json`, `images-*.json` and
`workloads-*.json`. A partial group's PASS is not a complete S6 result. The
manifest records exact commands, return codes, source/executable/image hashes,
repository states and tool versions. Each subprocess has a 30-minute host
timeout, in addition to the simulator's cycle limit. Real Flash loading and
PSRAM traffic make the RT-Thread runs substantially slower than SRAM tests.

| File | Independent check |
| --- | --- |
| `preempt.S` | Two peers rendezvous six times with no call/yield/ECALL; distinct register sentinels survive timer-driven switches |
| `rtthread-system.c` | Scheduler hooks, timer sleep/wakeup, idle execution, local/heap data, heap restoration, stack fill patterns |
| `include/rtconfig.h` | Fixed single-core kernel subset, 100 Hz ticks, heap and stack checks, scheduler/idle hooks |
| `uart-long.c` | Reprogram UART divisor to 8; send 528 bytes through AM's THRE polling and TEMT completion |

`--stack-region NAME:LOW:HIGH` in the harness records minimum architectural SP
for each ELF-derived stack interval. Thread fill-pattern scans and this SP
measurement describe the tested workload, not a proof of worst-case stack use.

`SOC_DELAY=1` uses [soc_delay.py](../../scripts/soc_delay.py) to generate a
simulation wrapper copy whose five AXI channels pass through
[soc_delay_channel.sv](../../sim/soc_delay_channel.sv). The maintained CPU/SoC
RTL is unchanged. `+npc_delay_seed=N`, `+npc_delay_max=N` and
`+npc_delay_fixed=0|1` configure bounded waits; fixed mode uses the maximum at
each gate. The shim is a registered channel even when the maximum is zero.
Normal `SOC_DELAY=0` remains the actual system timing without this shim.

System delay tests use real SoC devices, with instruction/IRQ DiffTest and final
SRAM/PSRAM comparison. Independent S1 responder tests provide injected
SLVERR/DECERR and protocol-error coverage; they are not relabeled as real-SoC
error injection. The real SoC separately checks its own invalid-access errors.

Implementation and acceptance evidence: [M5 S6](../../../docs/notes/post-c/5-ysyx-soc-integration/6-system-validation.md).
