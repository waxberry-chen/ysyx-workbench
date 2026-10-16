# NPC implementation inputs

M4 S1 freezes the first synthesis top as `ysyx_core_axi4lite`: Core (including
IFU/LSU adapters) and Arbiter, with all existing commit/monitor ports retained.
The RTL includes the existing 32-entry GPR and combinational M arithmetic;
the RV32E software target does not remove that hardware.
No parameter overrides: the Core defaults to `PC_RST=0x80000000`, `IFQ_DEPTH=2`.

`filelists/core.f` is a source-only, ordered SystemVerilog list. Resolve entries
against **npc/**, not this directory; tools run from npc/ or resolve absolute
paths against that root. The primitive source includes
`./vsrc/gnrl/ysyx_global.sv`, also relative to npc/. The list intentionally excludes
legacy DPI RAM, B1 top/slaves, Xbar, random shims, testbenches and C++ harness.

Implementation defines `SYNTHESIS`; do not define `NPC_SIM_DPI`, `DEBUG`, `DIFF`
or `B1_SIM_SHIM`. `SYNTHESIS` removes SVA and overrides `NPC_SIM_DPI` even if
both are supplied. Normal NPC simulation enables `NPC_SIM_DPI` explicitly for
GPR/CSR observation, without `SYNTHESIS`, so assertions remain available.
Neither switch changes datapath/reset logic. GPR x1–x31 have explicit reset-to-zero;
x0 reads as a constant zero. Reset must be asserted before executing software.

Local S1 checks (from the repository root):

```bash
make -C npc synthesis-scope-check
make -C npc architectural-state-test
```

These check source preprocessing/lint and RTL behavior, **not DC synthesis or
PT timing**. DC/PT scripts and numeric SDC constraints will be implemented in S2.
The design scope, reset audit, SDC interface requirements and evidence are recorded
in [M4 S1](../../docs/notes/post-c/4-pre-soc-signoff/1-synthesis-scope.md).
