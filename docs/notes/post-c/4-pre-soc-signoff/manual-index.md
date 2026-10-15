# M4：DC/PT 手册检索入口

2026-10-15：两本 PDF 已使用 `pdftotext -layout -enc UTF-8` 生成本地缓存，保留每页末尾的 `\f`（form feed，字节 `0x0c`）。不使用 `-nopgbrk`，不把全文载入对话作为常驻上下文。以下命令从仓库根目录执行。

## 1. 文件、版本与缓存

| ID | 原始手册 | 版本 | PDF 页数 / 分页符数 | 本地文本缓存 |
| --- | --- | --- | --- | --- |
| `dc` | [Design Compiler User Guide](<../../../userguide/Design Compiler User Guide Version P-2019.03, March 2019.pdf>) | P-2019.03 | 792 / 792 | [dc-P-2019.03.txt](../../../userguide/.cache/dc-P-2019.03.txt) |
| `pt` | [PrimeTime User Guide](../../../userguide/PrimeTime_User_Guide_2016.pdf) | L-2016.06 | 1066 / 1066 | [pt-L-2016.06.txt](../../../userguide/.cache/pt-L-2016.06.txt) |

生成信息在本地 [manifest.json](../../../userguide/.cache/manifest.json)：PDF 与缓存 SHA-256、手册版本、PDF 页数、分页符数量、pdftotext 版本及选项。PDF 和缓存沿用仓库现有忽略规则，不提交生成的全文；本索引和 [manuals.py](manuals.py) 随 M4 文档维护。

`docs/userguide/` 的 PDF 仍由用户本地提供；换机器或清理缓存后先运行 `build`。换版本/文件名时先更新 `manuals.py` 的 `GUIDES`，并重新核对下文页码索引。

## 2. 查询与按页阅读

先按命令/主题定位，默认最多返回 20 个命中行。搜索为大小写不敏感的字面匹配，不是正则表达式；输出包含 **PDF 页码（从 1 开始）和该页文本行号**。

```bash
python3 docs/notes/post-c/4-pre-soc-signoff/manuals.py search dc 'target_library' --from-page 35 --limit 10
python3 docs/notes/post-c/4-pre-soc-signoff/manuals.py search pt 'report_analysis_coverage' --from-page 38 --limit 10
python3 docs/notes/post-c/4-pre-soc-signoff/manuals.py page dc 111 --count 2
python3 docs/notes/post-c/4-pre-soc-signoff/manuals.py page pt 656 --count 2
```

`--from-page` 可跳过前置目录，也可从上一轮命中后继续查找；重复命中常来自目录、正文或索引，需要阅读附近小节确认上下文。跨行标题可能不匹配，应缩短关键词或拆分查询。`page` 默认读一页；一般一次读 1–3 页即可。脚本在每次查询前核验 PDF/缓存 hash，发现变化即要求重建，避免引用旧页码。

需要正则检索时，可直接使用 `rg`，但必须显式给缓存路径（该目录被 Git 忽略）：

```bash
rg -n -i 'target_library|link_library' docs/userguide/.cache/dc-P-2019.03.txt
rg -n 'check_timing|report_analysis_coverage' docs/userguide/.cache/pt-L-2016.06.txt
```

`rg -n` 给出全文行号，不能当成 PDF 页码；需要准确页码时使用 `manuals.py search`。图、表格、公式或提取顺序含糊时，回到原 PDF 对应页面，不能仅凭文本推断图形含义。

## 3. 重建与校验

依赖为本机 Python 3、Poppler 的 `pdftotext` 和 `pdfinfo`。构建只读取两本手册，写入 `docs/userguide/.cache/`，不调用 EDA 或网络。

```bash
python3 docs/notes/post-c/4-pre-soc-signoff/manuals.py build
python3 docs/notes/post-c/4-pre-soc-signoff/manuals.py check
```

`build` 实际对每本执行以下形式的命令，并记录/校验分页符数与 PDF 页数一致：

```bash
pdftotext -layout -enc UTF-8 \
  'docs/userguide/Design Compiler User Guide Version P-2019.03, March 2019.pdf' \
  docs/userguide/.cache/dc-P-2019.03.txt
pdftotext -layout -enc UTF-8 \
  docs/userguide/PrimeTime_User_Guide_2016.pdf \
  docs/userguide/.cache/pt-L-2016.06.txt
```

优先通过 `build` 重建，确保 manifest 同步更新；直接运行 pdftotext 后若输出 hash 改变，查询工具会拒绝沿用旧 manifest。拆页使用 `text.split("\f")`，末尾的空字符串不是额外页面；不要用 `splitlines()` 来计算页数，它也会消耗 form feed。

## 4. 当前 M4 的主题索引

以下为当前两份 PDF 实际核对的阅读起点，并非要求整章通读。正文页码采用手册印刷的“章-页”，与 PDF 页序不同；不能用一个固定偏移换算所有章节。

| M4 问题 | 手册小节 / 阅读起点 | PDF 页 | 正文页 | 建议检索词 |
| --- | --- | ---: | --- | --- |
| 普通综合与 TOPO 的区别 | DC：Wire Load Mode；The Synthesis Flow | 57、73 | 2-3、2-19 | `wire load`、`topographical` |
| 库搜索、target/link 区别 | DC：Setting Up and Working With Libraries | 111 | 4-1 | `search_path`、`target_library`、`link_library` |
| SV 输入、展开与链接 | DC：Reading Designs；Linking Designs | 153、159 | 6-3、6-9 | `analyze`、`elaborate`、`sverilog`、`link` |
| 网表/数据库输出 | DC：Saving Designs | 186 | 6-36 | `write`、`write_sdc`、`ddc` |
| I/O 环境及互连估算 | DC：Defining the Design Environment；Wire Load Models | 193、202 | 7-1、7-10 | `set_load`、`set_driving_cell`、`set_wire_load_model` |
| 约束与优化 | DC：Defining Design Constraints；Optimizing the Design | 217、371 | 8-1、11-1 | `create_clock`、`set_input_delay`、`compile_ultra` |
| 综合检查与面积 | DC：Checking Designs and Libraries Before Synthesis；Analyzing Area | 703、706 | 24-7、24-10 | `check_design`、`report_area`、`report_qor` |
| 附带功耗报告的模式限制 | DC：Power Correlation（TOPO 上下文） | 209 | 7-17 | `report_power`、`set_switching_activity` |
| PT 最小分析流程 | PT：The PrimeTime Static Timing Analysis Flow | 57 | 2-7 | `read_verilog`、`link_design`、`read_sdc` |
| Design/I/O 约束与 wire load | PT：Design-Level Constraints；Wire Load Models | 145、153 | 5-1、5-9 | `set_input_delay`、`set_output_delay`、`wire load` |
| 时钟建模 | PT：Clocks | 171 | 6-1 | `create_clock`、`set_clock_uncertainty`、`ideal` |
| 路径与例外 | PT：Timing Paths and Exceptions | 229 | 7-1 | `set_false_path`、`set_multicycle_path` |
| STA 报告与漏约束检查 | PT：Reporting and Debugging Analysis Results；Analysis Coverage Report | 633、656 | 17-1、17-24 | `check_timing`、`report_timing`、`report_analysis_coverage` |

特别是 `report_power`：命中 PDF 209 的段落讨论 TOPO 的 clock-tree power correlation，不能据此认为当前普通综合具备相同物理估算能力。需要继续核对命令的模式限制和服务器版本帮助。查到一个命令名称，并不等于已找到支持当前使用方式的依据。

## 5. 后续搭建 flow 的查阅约定

1. 对模式、约束、默认行为、命令选项或报告含义有疑问时，先搜索这里的本地缓存，阅读相关小节及限制，再修改 NPC flow；旧参考脚本只证明旧工程怎样写，不能代替命令语义依据。
2. 记录依据格式：`DC P-2019.03，章节/正文页，PDF 页 N`，或对应 PT 格式；同时注明适用 wire-load/TOPO、pre-layout/post-route 模式。
3. 手册版本不是服务器版本声明。参考配置曾指向 DC O-2018.06-SP1，当前 DC 手册为 P-2019.03，PT 手册为 L-2016.06；实际执行时核对工具版本，具体选项以对应工具 `help`/`man` 为准，未核对则标记待验。
4. User Guide 偏重流程与概念，不能假定包含完整 Command Reference。缓存中查不到或说明不足时，记录待核对的命令与问题；后续从服务器工具帮助获取，不编造选项。
5. 本索引服务于当前 DC/PT 面积时序基线和附带 DC 功耗粗估。读到物理实现、四值/GLS 或 PTPX 章节不自动扩大 M4 范围。
