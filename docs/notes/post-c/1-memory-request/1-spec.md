# 1 - 可变延迟 Memory Request/Response 规划文档

此文档用于规划完成 ysyx 增量点1: 可变延时访存握手 的实现. 

## 主要计划加入的模块: 

### 1. CPU 中一个 Main FSM

用于控制 CPU 状态, 放在 `npc/vsrc/core/ysyx_core.sv` 中, 当前阶段预计先引入 Instruction fetch interface 的握手访存. 
FSM 暂时 3 个 states (2-bit 二进制编码): 
- IF_REQ: req_valid = 1; if (req_valid && req_ready) next_state = IF_WAIT;
- IF_WAIT: rsp_ready = 1; if (rsp_valid && rsp_ready) next_state = EXEC;
- EXEC: will_commit = 1; we = 1; renew pc; if (will_commit == 1) next_state = IF_REQ;

if !ready (req_valid && req_ready != 1, not fire) , valid/payload remain unchange;

Q: 我这个状态机应该放在顶层 `ysyx_core.sv` 模块中还是放在 `npc/vsrc/core/ysyx_i_ram.sv` 中? 似乎应该放在后者中, 这样 i_ram 模块不需要将valid/ready 信号做成 input/output. 但是 EXEC 又是整个 cpu 的状态. 感觉不好决定. 

### 2. 上述 FSM 隐含的 2-channel RAM 接口

拉出 valid-ready 信号组到顶层, 或使用 DPI-C 函数绑定指针到对应的 valid-ready 信号组, 然后在 C++ RTL Harness 中写 slave 逻辑与随机延时. 

### 3. inst register 用于保存指令

## 第一轮 Review

整体方向正确，第一轮只改 instruction fetch 是合适的增量边界。评审后的暂定决策如下。

### 1. Main FSM 属于 CPU requester

`IF_REQ/IF_WAIT/EXEC` 描述 CPU 能否取指、执行和提交，因此先放在 `ysyx_core.sv`，不放入 `ysyx_i_ram.sv`。以后若拆分 IFU，可将 fetch request/wait 状态下沉到 IFU，但 memory slave 不应知道 `EXEC` 或参与决定 CPU commit。

状态语义调整为：

- `IF_REQ`：保持 `i_req_valid/i_req_addr`，request handshake 后进入 `IF_WAIT`；
- `IF_WAIT`：保持 `i_rsp_ready`，response handshake 时锁存 `inst_q/inst_pc_q`，进入 `EXEC`；
- `EXEC`：使用锁存指令完成架构状态更新，`commit_valid=1`，随后进入 `IF_REQ`。

第一版约定 response 最早在 request handshake 后一个周期出现，每个 port 最多一个 outstanding request。

### 2. 必须增加指令寄存器和副作用门控

可变延迟后不能继续直接译码 memory response，需要增加 `inst_q/inst_pc_q`。在 `IF_REQ/IF_WAIT` 中它们会保留上一条指令，因此所有 decoded intent 都必须由 `state==EXEC` 门控，包括：

```text
PC enable、GPR write、CSR write、trap/mret、load/store enable、commit
```

只冻结 PC 不够，否则上一条 store、CSR 或 trap 指令可能在等待取指时重复产生副作用。`will_commit` 暂时可直接定义为 `state==EXEC`，不必再用它决定从 `EXEC` 跳转到 `IF_REQ`。

### 3. 握手使用显式顶层端口

选择将 instruction request/response 信号拉到 `ysyx_core` 顶层，由 Verilator harness 或 simulation wrapper 驱动。暂不使用 DPI-C 指针绑定 valid/ready；功能接口应在 RTL 端口和波形中显式可见，并能够在未来替换为 AXI adapter 或 ysyxSoC。

推荐边界：

```text
ysyx_core request/response ports
  -> simulation memory slave
  -> paddr_read/write
  -> C++ pmem/MMIO
```

`paddr_*` 继续作为存储和设备 backend，但每个 transaction 只能调用一次，不能在组合求值或等待周期中反复调用。

### 4. 随机延迟属于验证环境

不把 LFSR 随机延迟逻辑放进 CPU 或真实 SRAM DUT。第一版优先在 C++ harness 中实现单 outstanding memory slave：request handshake 时保存 payload，等待固定/随机周期后调用一次 backend 并返回 response。随机 seed 必须可配置和记录。

### 5. 第一轮实现范围

1. `ysyx_core` 加入三状态 FSM；
2. 增加 `inst_q/inst_pc_q`；
3. 增加 instruction request/response 顶层端口；
4. C++ slave 先实现固定一周期响应；
5. 所有架构副作用仅在 `EXEC` 生效；
6. `commit_pc/commit_inst/commit_is_mmio` 与锁存指令对齐；
7. 通过 CPU tests、hello、RTC 和 trap 回归；
8. 再逐步加入 5/10/20-cycle 和可复现随机延迟。

第一轮暂不同时引入 D-port request/response、AXI、arbiter/Xbar、Cache、流水线或 byte-lane/WSTRB 重构。instruction fetch 稳定后，再以同一 transaction contract 改造 load/store。
