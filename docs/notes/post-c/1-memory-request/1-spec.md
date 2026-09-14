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

我初步设想有两个可选项: 
1. 拉出 valid-ready 信号组到顶层, 或使用 DPI-C 函数绑定指针到对应的 valid-ready 信号组, 然后在 C++ RTL Harness 中写 slave 逻辑与随机延时. 
2. 直接添加一个 SRAM 模块作为 slave, 在其中用 LSFR 作为访存延时随机数, 保留 pmem_read(), pmem_write() 形式的接口. 
