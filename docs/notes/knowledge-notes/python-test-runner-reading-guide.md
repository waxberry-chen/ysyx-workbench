# 读懂 Python 测试脚本：从对象来源到一次测试判定

2026-10-25。以 `npc/tests/m5_s3_test.py` 为例。目标是能阅读、解释并小幅修改测试编排脚本；先掌握这里实际使用的接口，不要求先学完 Python 面向对象设计。

先读 [SoC 仿真与验证入门](soc-simulation-and-verification-basics.md)。本文假定已知道 Python 在宿主机启动仿真 EXE，而不是在目标 CPU 中运行。

## 1. `aaa.bbb` 到底是什么意思

在 Python 中，名字关联对象，对象具有类型。**`aaa.bbb` 表示取得 `aaa` 的一个名为 `bbb` 的属性**；具体含义取决于 `aaa` 是什么。

| 写法 | `aaa` 是谁 | 点号后是什么 |
| --- | --- | --- |
| `subprocess.run` | 导入的模块 | 模块提供的函数 |
| `result.returncode` | 一次进程执行的结果对象 | 保存退出码的属性 |
| `image.name` | 表示文件路径的 `Path` 对象 | 文件名属性 |
| `image.read_bytes` | 同一个路径对象 | 读取文件内容的方法 |

**模块**组织函数、类等名字；**类**描述一种对象类型及其操作；**实例**是这种类型的具体对象。`from pathlib import Path` 导入一个类；`Path("hello.bin")` 创建一个表示该路径的实例。调用类也使用括号。

方法是通过对象访问的操作。`image.read_bytes()` 会读取 `image` 所指文件，返回 `bytes`；`image.read_bytes` 只取得这个方法，还没有读取文件。`image.name` 已经是文件名，不应该再写成 `image.name()`。

初读时先辨认三种语法：`.name` 取属性，`(...)` 调用，`[...]` 按键或下标取内容。比如 `summary["pass"]` 是取字典中的值，不能换成 `summary.pass`。语言机制可查 [Python：类与属性](https://docs.python.org/zh-cn/3/tutorial/classes.html)。

## 2. 怎么知道有哪些对象、有哪些操作

对象不需要凭空猜。先沿着**导入、赋值、函数参数、函数返回值**追踪来源：

```python
import subprocess
from pathlib import Path

image = Path("hello.bin")     # 构造 Path 对象
size = image.stat().st_size    # stat() 返回信息对象，再取 st_size
```

第二行可以拆成 `info = image.stat()` 和 `size = info.st_size`。于是查找链变成：`Path` 文档 → `stat()` 返回什么 → 返回对象有哪些属性。每次只解决一个未知，不必背下整个库。

实现新功能时，先把需求改写成操作，再找库：

| 想完成的操作 | 当前工程使用的入口 | 先确认什么 |
| --- | --- | --- |
| 拼路径、读写文件、查文件大小 | `pathlib.Path` | 返回路径、文本、字节，还是文件信息？ |
| 启动 EXE，等待结束，取日志和退出码 | `subprocess.run` | 命令参数、超时、输出捕获、失败如何表达？ |
| 将 JSON 文件解释成 Python 数据 | `json.loads` | 输入文本；当前报告的最外层对象变成字典 |
| 按行读取提交/总线 CSV | `csv.reader` | 各列先是字符串；哪些列需按十六进制转整数？ |
| 求镜像指纹 | `hashlib.sha256` | 输入字节；用于记录产物，不负责判断硬件正确性 |

在小实验中可以用 `type(obj)` 看类型，用 `help(Path.read_bytes)` 看说明，用 `dir(obj)` 浏览候选属性。`dir` 不是接口语义的解释，也不保证列出所有动态属性。IDE 的悬停、补全和“跳转到定义”是同样思路。[Python 内置函数](https://docs.python.org/zh-cn/3/library/functions.html) 是这些工具的依据。

当前脚本中的 `run`、`build`、`simulate` 是项目作者定义的函数，应在本文件查 `def`；`subprocess.run` 是标准库接口，应查标准库文档。先判断名字属于哪一边。

## 3. 先记住脚本中几种常见值

| 类型 / 写法 | 意义 | 本工程例子 |
| --- | --- | --- |
| `str`：`"M\n"` | 文本；这里 `\n` 表示换行 | 日志、文件名、JSON 文本 |
| `bytes`：`b"M\n"` | 字节序列，此例为 `4d 0a` | UART 预期、BIN 内容 |
| `int`：`20000000` | 整数 | 周期上限、退出码 |
| `bool`：`True` / `False` | 布尔值 | 是否输出 trace、某项检查是否成立 |
| `None` | 没有提供值 | `expected_uart=None` 表示不检查 UART 字节 |
| `list`：`[EXE, "--mrom", image]` | 有序列表 | 命令参数；每个元素对应一个参数 |
| `dict`：`{"pass": True}` | 键到值的映射 | 解析后的 JSON 摘要 |
| `Path` | 表示路径的对象 | 通过方法读取文件；对象本身不是文件内容 |

`"M\n"` 和 `b"M\n"` 类型不同；文本与原始字节比较会出错。`.read_text()` 返回 `str`，`.read_bytes()` 返回 `bytes`。`b""` 是“预期没有任何 UART 字节”，`None` 是“不作这项检查”，两个条件不能混淆。

`bytearray` 是可以按位置修改的字节序列。S3 用它复制正常 BIN 的内容、替换 store 的四个字节，再写出负例镜像。普通 `bytes` 不能直接修改元素。

## 4. 拆开三种容易让人卡住的表达式

### 4.1 路径不是字符串拼接

```python
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "npc" / "build" / "m5-s3"
```

`__file__` 是当前脚本文件的路径；`resolve()` 得到解析后的绝对路径。对 `仓库/npc/tests/m5_s3_test.py`，`parents[0]` 是 `tests`，`parents[1]` 是 `npc`，`parents[2]` 才是仓库根目录。交互式解释器通常没有这个脚本变量。

`Path` 定义了 `/` 运算用于拼接路径。这里只构造一个路径值，没有自动创建目录；创建目录需调用 `mkdir`。这些行为可查 [pathlib 文档](https://docs.python.org/zh-cn/3/library/pathlib.html)。

### 4.2 从文件到字典，是几次不同操作

```python
summary = json.loads((OUT / f"{name}.json").read_text())
```

`f"{name}.json"` 将变量值放入文本；`name = "hello"` 时得到 `"hello.json"`。原式可以逐句阅读为：

```python
filename = f"{name}.json"    # str：文件名
path = OUT / filename       # Path：文件的位置
text = path.read_text()     # str：文件中的 JSON 文本
summary = json.loads(text)  # dict：当前报告最外层是 JSON object
passed = summary["pass"]   # bool：具体字段的值
```

`json.loads` 解析文本，不会自行打开文件；其他 JSON 内容也可能解析成列表、数字等类型。当前 `main.cpp` 写的是对象，所以这里得到字典。详见 [json 文档](https://docs.python.org/zh-cn/3/library/json.html)。

### 4.3 函数参数、返回值与副作用

```python
def simulate(name, image, trace=False, expected_uart=None):
    # 组织命令、运行 EXE、检查输出……
    return summary

summary = simulate("hello", image, expected_uart=b"Hello, ysyxSoC!\n")
```

`def` 定义函数，调用时才运行函数体。`trace=False` 是默认参数；调用中的 `expected_uart=...` 是按名字传参。`return` 把值交回调用者。上面的函数体仅表示阅读结构，不是可直接运行的完整实现。

函数还可能产生**副作用**：写文件、启动进程、改变列表。当前 `simulate` 返回字典，但它做的工作远不止返回数据。阅读函数时填写“输入、输出、副作用、失败条件”四项即可抓住主干。

## 5. 先读 `run()`：宿主机怎样运行 EXE

以下是当前 `run()` 的核心操作，保留原有参数含义：

```python
result = subprocess.run(
    list(map(str, args)), cwd=cwd,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
text = result.stdout.decode(errors="replace")
(OUT / f"{name}.log").write_text(text)
```

`list(map(str, args))` 将每个参数转成字符串，等价于先建空列表，再逐项 `append(str(arg))`。因为原列表同时包含 `Path`、整数和字符串，转换后可以统一作为命令参数传递。

`cwd` 指定子进程的工作目录。`stdout=PIPE` 捕获标准输出，`stderr=STDOUT` 将错误输出合并进来；没有启用文本模式，因此 `result.stdout` 是 `bytes`，再用 `decode` 转成文本。`timeout=240` 是宿主机等待的秒数，和 EXE 的 `--max-cycles` 属于不同计量。

调用会等待子进程结束，返回 `CompletedProcess` 对象；其 `returncode` 是退出码。默认不会因为非零退出码自动抛异常，所以脚本能自己检查预期失败；超时则会抛出 `TimeoutExpired`。参数语义见 [subprocess 文档](https://docs.python.org/zh-cn/3/library/subprocess.html)。

当前函数随后区分：普通运行要求退出码为零；传入 `expected` 时要求非零退出且日志含指定错误文本。这里 `expected` 是**错误信息片段**，不是 UART 预期。函数最后 `return result.returncode, text` 返回两个值，调用者可以用 `rc, text = run(...)` 接收。

## 6. 再读 `simulate()`：运行成功还要检查什么

当前函数组织的参数中，`--mrom` 指定 BIN，`--diff` 指定参考库，`--summary` 和 `--uart-log` 指定结果文件。`expected_uart` 留在 Python 中用于比较，没有作为 EXE 的命令行参数传进去。

调用 `run()` 后，脚本读取 JSON，并作如下检查：

```python
assert summary["pass"]
assert summary["diff_steps"] == summary["commits"]
assert summary["diff_sram_checks"] == 1
assert summary["flash_dpi_calls"] == 0
if expected_uart is not None:
    assert (OUT / f"{name}.tx").read_bytes() == expected_uart
```

这些条件分别要求 harness 没有报错、逐次提交有差分步骤、完成一次结束时的 SRAM 比较、本阶段没有意外访问 Flash，以及 UART 字节符合预期。当前完整函数还检查栈使用边界；这些检查依据的是本工程的测试范围。

`assert 条件` 在条件为假时抛出 `AssertionError`，通常使脚本以失败结束。当前测试依赖这些断言，因此用普通 `python3` 执行，不使用会去掉断言的 `python3 -O`。

然后再读 `main()` 中的测试顺序。只有想理解“怎样生成镜像”时才进入 `build()`；想理解“如何破坏启动”时才进入 `negatives()`。第一遍可略过 `symbols()` 的压缩写法和汇编补丁的位操作。

## 7. 一个完整的小实验：看见对象和判定过程

下面可以直接保存成临时 `.py` 文件，用 `python3` 运行。它使用 Python 子进程模拟“产生退出码和输出的外部程序”，不依赖 SoC 构建；这里只练习编排方法，不能替代 RTL 测试。`sys.executable` 是当前 Python 解释器路径，`-c` 表示执行紧随其后的代码文本。

```python
import json
import subprocess
import sys

command = [sys.executable, "-c",
           'print(\'{"pass": true, "commits": 3}\')']
result = subprocess.run(command, capture_output=True,
                        text=True, check=False, timeout=5)
assert result.returncode == 0
summary = json.loads(result.stdout)
assert summary["pass"] and summary["commits"] == 3
print(type(result).__name__, type(result.stdout).__name__,
      type(summary).__name__)  # CompletedProcess str dict

bad_command = [sys.executable, "-c",
               'print("EXPECTED_FAIL"); raise SystemExit(1)']
bad = subprocess.run(bad_command, capture_output=True,
                     text=True, check=False, timeout=5)
assert bad.returncode != 0 and "EXPECTED_FAIL" in bad.stdout
print("正常例和预期失败例均通过")
```

这里使用 `text=True`，所以不需要手工 `.decode()`。`capture_output=True` 分别捕获标准输出和错误输出，分别在 `.stdout`、`.stderr`；与工程脚本合并输出的方式略有不同。

纸上也可以做两次预测：把检查中的 `commits == 3` 改为 `== 4`，第一例应报断言失败；把第二条子进程代码改为正常退出，负例检查也应失败。测试通过的条件由检查器决定，不能只看被运行程序有没有打印文字。

## 8. 遇到陌生代码时怎么继续

先写下对象来源和类型，再把连续操作拆成临时变量。查标准库的参数及返回值，最后用几行小实验确认理解。例如，面对 `image.stat().st_size`，答案应是“路径 → 文件信息对象 → 文件大小整数”，而不是把整行当成一个需要背诵的咒语。

本阶段达到以下程度就可以继续阅读 S3：能解释 `Path → 文件内容 → dict` 的转换，能获取 EXE 的返回码和日志，能设置一个正常例与一个预期失败例，并能定位检查条件。继承体系、装饰器、自定义复杂类及标准库内部实现暂时不影响这些任务。
