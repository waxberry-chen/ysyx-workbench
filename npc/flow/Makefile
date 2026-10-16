# 阅读入口：Makefile → 00_indata/configs → 01_common → 02_syn → 03_sta。
# DC（Design Compiler）把 RTL 综合成标准单元网表；PT（PrimeTime）对网表做静态时序分析。
# 完整使用方法见 README.md；本文件仅将 make 参数传给统一 driver，避免重复实现检查逻辑。
PYTHON ?= python3
# CONFIG 是设计假设，SITE 是服务器的工具/工艺库配置；两者分开才能换机器而不改变设计目标。
CONFIG ?= 00_indata/configs/npc_core.tcl
SITE ?= 00_indata/configs/site.example.tcl
# RUN_ROOT/RUN_ID 用于新建运行；RUN 用于继续同一次运行的 STA 或检查其结果。
# make -C npc/flow 会把工作目录切到本文件所在目录，下面的相对路径据此解析。
RUN_ROOT ?= build
RUN_ID ?=
RUN ?=
.PHONY: check test preflight probe synth sta all inspect clean
# 本地入口：只需 Python/Tcl，不启动 DC/PT。test 中的工具与报告是模拟对象。
check:
	$(PYTHON) 01_common/flow.py check --config "$(CONFIG)" --site "$(SITE)"
test:
	$(PYTHON) -m unittest discover -s 04_tests -v
# 服务器入口：preflight 只检查文件/配置/可执行路径，不证明 license 或 EDA 命令可用。
preflight:
	$(PYTHON) 01_common/flow.py preflight --config "$(CONFIG)" --site "$(SITE)"
# probe 读库确认属性；synth 执行 DC；all 顺序执行 DC 和 PT。三者都新建 run。
probe synth all:
	$(PYTHON) 01_common/flow.py $@ --config "$(CONFIG)" --site "$(SITE)" --run-root "$(RUN_ROOT)" $(if $(RUN_ID),--run-id "$(RUN_ID)")
# sta 读取 RUN 中已成功的 DC 产物；inspect 重新核查产物，不重跑 EDA。
sta inspect:
	$(PYTHON) 01_common/flow.py $@ --run "$(RUN)"
# 只删除指定 run；不会清空 build、00_indata 或其他 run。清理后可复用同一 ID。
clean:
	$(PYTHON) 01_common/flow.py clean --run-root "$(RUN_ROOT)" --run-id "$(RUN_ID)" $(if $(RUN),--run "$(RUN)")
