# 阅读综合网表与 STA 报告：层次、实例、引脚和网络

2026-10-18。以下实例取自 NPC 的 `core-tt-5ns-baseline`，对应 [M4 第 03 次实验](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/README.md)。实例名仅适用于这一次映射结果；本笔记保留必要网表片段，便于原 build 目录清理后回顾。

后续范围决定（2026-10-18）：用户已选择在下一次早期 run 中对 rst_n 设置 false path，将 reset 时序登记为 deferred，见 [reset TODO](../post-c/4-pre-soc-signoff/reset-timing-todo.md)。这不改写本文 synth 03 的事实，也不代表脉宽验证通过；本次决定属于明确的评估范围调整。

## 1. 先区分四种对象

| 对象 | 本次例子 | 含义 |
| --- | --- | --- |
| 模块 / 库单元类型 | `ysyx_exu`、`BUFFD1BWP12T40P140` | 实例所引用的定义；标准单元的功能、引脚和时序模型来自库 |
| 实例（instance / cell） | `u_exu`、`U4` | 某种类型在设计中的一次具体实例化 |
| 引脚（pin） | `U4/I`、`U4/Z` | 实例的连接点，有输入、输出等方向和具体功能 |
| 网络（net） | `op_pc[0]`、`trap_epc[0]` | 连接引脚或端口的导线；自身不是逻辑单元 |

顶层接口通常作为 port 对象访问，实例接口作为 pin 对象访问。层次模块的端口将模块内外的网络连接起来；同一连接在不同层次中可以使用不同信号名。

## 2. 如何拆解报告中的层次路径

```text
core/u_exu/U4/Z
│    │     │  └─ 引脚名 Z
│    │     └──── 标准单元实例名 U4
│    └────────── EXU 实例名 u_exu
└────────────── core 实例名 core
```

这里的 `core`、`u_exu`、`U4` 都是 **instance name**，不是 module/type name。当前 top 是查询的根，报告通常不再把 top 名称加在前面。

对应的实例化关系是：

```verilog
// 当前 top 内：
ysyx_core core (...);

// ysyx_core 模块内：
ysyx_exu u_exu (...);

// ysyx_exu 模块内：
BUFFD1BWP12T40P140 U4 (...);
```

同一模块定义可能被实例化多次，每个实例有自己的层次路径。不同模块内部也都可能存在一个名为 `U4` 的单元，因此搜索整个网表时，不能把第一个匹配的 `U4` 当作目标。

## 3. 怎样从引脚找到连接的信号

在该 run 的 `outputs/core.v` 中，沿实例层次进入 `ysyx_exu`，可以找到：

```verilog
BUFFD1BWP12T40P140 U4 (
    .I(op_pc[0]),
    .Z(trap_epc[0])
);
```

Verilog 的命名连接格式是 **`.引脚或端口名(当前层的连接信号)`**。本例的 `I` 是 buffer 输入，`Z` 是输出，因此连接为：

```text
op_pc[0] → U4/I → buffer → U4/Z → trap_epc[0]
```

所以报告中的 `core/u_exu/U4/Z` 对应驱动 EXU 内部的 `trap_epc[0]`。若要继续追踪，需要查看父层的端口连接：

```verilog
ysyx_exu u_exu (
    // 省略其他端口
    .trap_epc(exu_trap_epc)
);
```

这说明 EXU 的 `trap_epc` 接到父层的 `exu_trap_epc`。继续检查它的负载，可找到 CSR；本项目 CSR 对 EPC 执行 `& 32'hfffffffc`，低两位不参与存储。本次映射网表中，相关 buffer 保留，但低两位没有有效负载，从而出现在最小电容违例报告中。

**看到输出引脚接到一个有名字的 net，不等于该 net 有接收负载。** 要确认负载，必须继续寻找消费者，尤其注意层次端口、未连接输出及被优化掉的位。输入 pin 通常是该网络的负载，输出 pin 通常是驱动端；方向应依据单元定义判断。

## 4. 常见引脚名称

引脚名由库定义，没有统一且固定的全集。下表是阅读线索，方向、有效电平、触发边沿和逻辑函数仍以实际 `.lib/.db` 或单元模型为准。

| 功能 | 常见名称 | 阅读提示 |
| --- | --- | --- |
| 组合逻辑输入 | `A/B`、`A1/A2/B1`、`I` | 逻辑门或 buffer 的输入 |
| 组合逻辑输出 | `Z/Y`、`ZN/YN` | 带 N 常表示反相输出，不能仅凭名称决定完整函数 |
| FF 数据输入 | `D` | 触发器采样的数据 |
| FF 数据输出 | `Q/QN` | 存储值及其反相值；单元不一定同时提供两者 |
| 时钟输入 | `CP/CK/CLK` | 触发器时钟；名称本身不能证明上升沿或下降沿触发 |
| 异步清零 | `CDN/RN/RESETN` | 常见为低有效，作用是清零到 0 |
| 异步置位 | `SDN/SN/SETN` | 常见为低有效，作用是置位到 1 |
| 使能 | `E/EN/CE/G` | 可能是数据使能、锁存使能或时钟门控使能，取决于单元 |
| 扫描接口 | `SI/SE` | 扫描数据输入、扫描使能 |
| 电源 / 地 | `VDD/VSS/VPWR/VGND` | 普通逻辑网表中可能隐含，物理实现仍需要电源连接 |

这里的 **`Z` 是引脚标识符，不是 Verilog 的高阻态 `1'bz`**。类似地，`CP` 是单元引脚名，`clk` 是本设计连接到它的信号名；两者不必相同。

## 5. 用本次 FF 实例阅读 D、Q、CP、CDN

```verilog
DFCNQD1BWP12T40P140 prefer_lsu_q_reg (
    .D   (n252),
    .CP  (clk),
    .CDN (n335),
    .Q   (prefer_lsu_q)
);
```

| 报告中的 pin 路径 | 当前模块内的连接 | 功能 |
| --- | --- | --- |
| `arbiter/prefer_lsu_q_reg/D` | `n252` | 数据输入 |
| `arbiter/prefer_lsu_q_reg/CP` | `clk` | 时钟输入 |
| `arbiter/prefer_lsu_q_reg/CDN` | `n335` | 低有效异步清零 |
| `arbiter/prefer_lsu_q_reg/Q` | `prefer_lsu_q` | 数据输出 |

若 coverage 报告写 `arbiter/prefer_lsu_q_reg/CDN(low)`，表示对 **CDN 引脚的低电平脉宽**进行检查，`(low)` 不是引脚名的一部分。`untested no_clock` 在本次对应缺少复位脉宽分析所需的波形信息，不能读成这个 FF 的 CP 没有时钟约束；具体背景见第 03 次实验记录。

STA 的 `Startpoint/Endpoint` 有时只打印寄存器实例名；详细路径表会进一步列出 `/CP`、`/Q`、`/D` 等引脚。最小电容报告则可以直接定位到输出 pin，它报告的是负载约束，不是完整的寄存器到寄存器路径。

## 6. `_reg` 是否由工具自动添加

本次 RTL 声明 `reg prefer_lsu_q`，在边沿触发的 always 块中赋值，综合后得到：

```text
RTL 状态变量：prefer_lsu_q
映射 FF 实例：prefer_lsu_q_reg
Q 端网络：   prefer_lsu_q
```

`_reg` 是工具推断寄存器时常见的命名习惯，**不是 Verilog 规定的后缀，也不是所有工具/配置都必须遵守的规则**。多位寄存器可能拆成逐位 FF，例如本次的 `addr_q_reg_14_`。flow 还执行 `change_names -rules verilog -hierarchy`，规范导出名称。

- 判断是否为 FF，应查看实际库单元类型和功能，不能仅看 `_reg`。
- RTL 中声明 `reg` 不保证得到 FF，是否形成存储取决于赋值行为。
- 优化可能删除、合并、复制或重新命名寄存器；RTL 变量与映射实例并不总是一一对应。
- 名称规范化、层次展开等也可能改变路径；不能将某次 run 的 `U4` 直接套用到另一次 run。

## 7. 回顾时的查找顺序

1. 确认报告和网表来自同一个 run、同一版本；本工程用 manifest 的 hash 追溯。
2. 拆解报告路径，区分层次实例、叶级实例和 pin。
3. 沿父层实例找到相应模块定义，再定位目标叶级实例。
4. 读取 `.pin(net)`，结合库单元定义确定方向和功能。
5. 沿 net 查驱动和负载；跨层时继续查看父层的端口连接。
6. 回到原报告，区分它检查的是数据时序、复位时序、脉宽还是电气负载。

长期证据入口：[03 实验总结与报告](../post-c/4-pre-soc-signoff/synthesis-results/03-200mhz-candidate/README.md)。完整映射网表由原 run 管理，不随知识笔记复制；本页片段用于解释阅读方法，不替代完整连通性检查。
