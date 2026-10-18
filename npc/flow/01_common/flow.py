#!/usr/bin/env python3
"""NPC DC/PT driver. Local checks never invoke EDA; execution is server-only."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

# 控制面与 EDA 分工：本文件负责输入、目录、进程和证据；Tcl 负责综合/时序命令。
# 生命周期：读取配置 → preflight → 冻结新 run → 执行 DC → 核对产物 → 执行 PT。
# 设计配置 cfg 与机器配置 site 都采用明确的键集合，拼错键不会悄悄沿用默认值。
FLOW = Path(__file__).resolve().parents[1]
NPC = FLOW.parent
REPO = NPC.parent
# Only maintained inputs/scripts enter snapshots; never recurse into build or PDK payloads.
SOURCE_DIRS = ('00_indata/configs', '00_indata/constraints', '00_indata/filelists',
               '01_common', '02_syn', '03_sta', '04_tests')
CFG_KEYS = set('top filelist sdc defines period input_min input_max output_min output_max uncertainty_setup uncertainty_hold clock_transition input_transition output_load source_latency_min source_latency_max max_cores power_enable power_toggle power_probability'.split())
SITE_KEYS = set('dc_shell pt_shell target_db library_name operating_condition corner vt time_unit capacitance_unit area_unit wire_load_model library_reviewed'.split())


class FlowError(RuntimeError):
    pass


def require(test, message):
    if not test:
        raise FlowError(message)


# 对输入内容求指纹，而非只比较文件名/时间戳；用于发现同名库或旧网表被替换。
# 分块读取以避免较大的服务器 DB/工具文件一次占满内存。
def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


# 先写临时文件再替换 manifest，减少中途失败留下半份 JSON 的机会。
def save(path, obj):
    path = Path(path)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + '\n')
    temp.replace(path)


def tcl_word(value):
    # Double-quoted Tcl word: do not allow paths/config strings to execute Tcl.
    value = str(value)
    for old, new in [('\\', '\\\\'), ('"', '\\"'), ('$', '\\$'), ('[', '\\['), (']', '\\]'), ('\n', '\\n'), ('\r', '\\r')]:
        value = value.replace(old, new)
    return '"' + value + '"'


# 配置在本地 Tcl 中解释，结果经固定编码传回 Python；此处不会调用 DC/PT。
# 这些 Tcl 文件是可信工程代码，不是供不可信输入使用的配置沙箱。
def load_config(config, site):
    for p in (config, site):
        require(Path(p).is_file(), f'Missing configuration: {p}')
    proc = subprocess.run(['tclsh', str(FLOW / '01_common/config_dump.tcl'), str(config), str(site)], capture_output=True, text=True)
    require(proc.returncode == 0, f'Configuration Tcl failed: {proc.stderr}')
    data = {'cfg': {}, 'site': {}}
    for line in proc.stdout.splitlines():
        parts = line.split('\t')
        require(len(parts) == 3 and parts[0] in data, f'Unexpected config output: {line}')
        group, key, value = parts
        data[group][key] = base64.b64decode(value, validate=True).decode()
    cfg, site_data = data['cfg'], data['site']
    for label, values, keys in [('design', cfg, CFG_KEYS), ('site', site_data, SITE_KEYS)]:
        require(set(values) == keys, f'{label} keys: missing={keys-set(values)}, unexpected={set(values)-keys}')
    require(cfg['top'] == 'ysyx_core_axi4lite', 'Wrong top: S1 scope is ysyx_core_axi4lite')
    require(cfg['defines'] == 'SYNTHESIS', 'Implementation defines must be exactly SYNTHESIS')
    for key in CFG_KEYS - {'top', 'filelist', 'sdc', 'defines'}:
        try:
            number = float(cfg[key])
        except ValueError as error:
            raise FlowError(f'{key} must be numeric') from error
        require(math.isfinite(number) and number >= 0, f'Invalid nonnegative value: {key}')
    require(float(cfg['period']) > 0 and float(cfg['output_load']) > 0, 'Period/load must be positive')
    for kind in ['input', 'output']:
        require(float(cfg[kind+'_min']) <= float(cfg[kind+'_max']) < float(cfg['period']), f'Invalid {kind} delay budget')
    require(float(cfg['source_latency_min']) <= float(cfg['source_latency_max']), 'Invalid source latency')
    require(cfg['power_enable'] in ('0', '1') and 0 <= float(cfg['power_probability']) <= 1, 'Invalid power activity')
    require(cfg['max_cores'].isdigit() and int(cfg['max_cores']) > 0, 'max_cores must be a positive integer')
    require(site_data['library_reviewed'] in ('0', '1'), 'library_reviewed must be 0 or 1')
    # 这里只校验 site 中的声明与当前 SDC 约定一致，不自动从 DB 推导单位。
    # 实际库单位由服务器 probe 报告人工核对；仅改字符串不会转换数值。
    require(site_data['time_unit'] == 'ns' and site_data['capacitance_unit'] == 'pf', 'SDC requires ns/pF; convert config/SDC explicitly for a different library')
    for key in SITE_KEYS - {'operating_condition'}:
        require(site_data[key].strip(), f'Empty site variable: {key}')
    require(Path(site_data['target_db']).is_absolute() and not any(c in site_data['target_db'] for c in '*?'), 'target_db must be one explicit absolute DB path')
    return data


# 返回两份清单：sources 按 filelist 顺序交给 analyze；files 是需要归档的完整输入。
# include 文件虽不作为独立编译源传入，也必须进入 hash 闭包，防止漏记宏定义变化。
# 这是 S1 的 source-only 清单约定，不是任意 Verilog filelist/预处理器的通用解析器。
def source_inputs(cfg):
    def local(name):
        path = (NPC / name).resolve()
        require(path.is_relative_to(NPC), f'Input escapes npc/: {name}')
        require(path.is_file(), f'Missing input: {path}')
        return path
    filelist = local(cfg['filelist'])
    sdc = local(cfg['sdc'])
    sources = []
    for raw in filelist.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        require(not line.startswith(('-', '+')) and line.endswith('.sv'), f'Not a source-only SV filelist entry: {line}')
        sources.append(local(line))
    require(sources and len(sources) == len(set(sources)), 'Empty/duplicate source list')
    require(sum(bool(re.search(r'\bmodule\s+'+re.escape(cfg['top'])+r'\b', p.read_text())) for p in sources) == 1, 'Top missing/duplicated in filelist')
    closure = set(sources)
    pending = list(sources)
    while pending:
        for include in re.findall(r'`include\s+"([^"]+)"', pending.pop().read_text()):
            path = local(include)
            if path not in closure:
                closure.add(path)
                pending.append(path)
    files = closure | {filelist, sdc}
    files.add(FLOW/'Makefile')
    for folder in SOURCE_DIRS:
        files |= {p for p in (FLOW/folder).rglob('*') if p.is_file()
                  and p.suffix in ('.tcl', '.sdc', '.py', '.f')
                  and '__pycache__' not in p.parts and not p.name.endswith('.local.tcl')}
    return sources, files


# preflight = 启动前检查。local 只检查本地配置/源码，不因本机缺 PDK 阻塞蒸馏。
# server 再检查真实 DB 和工具路径；probe 仅需 DC，不要求 operating condition 已填，
# 因为 probe 正是用来查询这些属性的。这里不启动工具，因此还没有验证 license。
def preflight(config, site_path, server=False, probe=False):
    data = load_config(config, site_path)
    sources, files = source_inputs(data['cfg'])
    if server:
        site = data['site']
        db = Path(site['target_db'])
        require(db.is_file() and db.stat().st_size > 0, f'Server library unavailable: {db}')
        if not probe:
            require(site['library_reviewed'] == '1' and site['operating_condition'], 'Run probe, review library units/PVT/Vt/model and set operating_condition + library_reviewed=1')
        for name in (['dc_shell'] if probe else ['dc_shell', 'pt_shell']):
            path = shutil.which(site[name])
            require(path, f'Server executable unavailable: {site[name]}')
            # 保留 dc_shell/pt_shell 的调用名：它们可能是公共 launcher 的符号链接，
            # launcher 可用 $0/argv[0] 分派产品。resolve() 会丢失该入口名。
            # 只转换为绝对路径，避免后续切换 cwd 使相对路径失效；文件 hash 仍会
            # 通过符号链接读取真实目标内容，所以保留入口不会取消输入内容校验。
            site[name] = os.path.abspath(path)
    return data, sources, files


# 本地检查分为 Tcl 文本结构检查和 SDC 对象契约检查；后者模拟 get_ports 等命令，
# 检测漏掉 min/max 的端口，不计算实际电路延迟，也不证明 Synopsys 选项兼容。
def local_check(config, site):
    data, sources, files = preflight(config, site)
    # Tcl's parser checks balanced syntax; the SDC mock verifies all port budgets.
    script = 'foreach p $argv {set f [open $p]; set s [read $f]; close $f; if {![info complete $s]} {error "Incomplete Tcl: $p"}}'
    proc = subprocess.run(['tclsh', str(FLOW / '04_tests/sdc_check.tcl'), str(config), str(NPC / data['cfg']['sdc']), str(NPC / 'vsrc/top/ysyx_core_axi4lite.sv')], text=True, capture_output=True)
    require(proc.returncode == 0, proc.stdout + proc.stderr)
    # stdin-mode Tcl otherwise may print errors and still exit 0; explicit catch/exit.
    code = 'set argv [list '+ ' '.join(tcl_word(p) for p in sorted(files) if p.suffix in ('.tcl', '.sdc')) + ']\nif {[catch {'+script+'} m]} {puts stderr $m; exit 1}\n'
    proc2 = subprocess.run(['tclsh'], input=code, text=True, capture_output=True)
    require(proc2.returncode == 0, proc2.stderr)
    print(proc.stdout.strip())
    print(f'LOCAL_CHECK_PASS: {len(sources)} SV sources; Tcl structure/SDC contract checked; EDA syntax/libraries/license NOT checked')


# 新建一次不可覆盖的实验：配置、RTL 和脚本固定后，运行中的原工作区可继续编辑。
# inputs 放快照；logs 保留进程原始输出；reports 放工具报告；outputs 放设计产物；
# work 放 DC 中间数据；launch 是空的启动 cwd，避免拾取工程目录的工具 setup。
def create_run(data, sources, files, config, site_path, run_root, run_id):
    run_id = run_id or datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', run_id), 'Invalid run ID')
    run = Path(run_root).resolve() / run_id
    require(not run.exists(), f'Run already exists; clean this RUN_ID explicitly or choose a new one: {run}')
    run.mkdir(parents=True)
    for folder in ('inputs', 'logs', 'reports', 'outputs', 'work', 'launch'):
        (run / folder).mkdir()
    for src in files:
        dest = run / 'inputs/npc' / src.relative_to(NPC)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
    shutil.copy2(config, run / 'inputs/design-config.tcl')
    shutil.copy2(site_path, run / 'inputs/site-config.tcl')
    # 写入已经求值的配置，而不是让 EDA 再次 source 可变的原始 site/config。
    # 每个值按 Tcl 字面量转义，路径中的空格、美元符号和方括号不能变成命令。
    lines = ['set run '+tcl_word(run)]
    for name, values in data.items():
        lines.append('set '+name+' [dict create '+' '.join(tcl_word(k)+' '+tcl_word(v) for k,v in values.items())+']')
    lines.append('set rtl_sources [list '+' '.join(tcl_word(p.relative_to(NPC)) for p in sources)+']')
    (run / 'inputs/run.tcl').write_text('\n'.join(lines)+'\n')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(REPO), *args], text=True)
    # HEAD 不足以描述未提交状态：还保存 dirty patch/status 和实际输入文件。
    # Git diff 不包含未跟踪文件内容，但 flow/RTL 快照已保存被选入的实际输入。
    (run / 'inputs/dirty.patch').write_text(git('diff', 'HEAD', '--binary'))
    (run / 'inputs/git-status.txt').write_text(git('status', '--short'))
    # 工艺库和工具只留 hash/原路径，不复制到仓库或快照，以免归档庞大的安装/PDK。
    external = {data['site']['target_db']: sha(data['site']['target_db'])}
    for name in ['dc_shell', 'pt_shell']:
        tool = Path(data['site'][name])
        if tool.is_file():
            external[str(tool)] = sha(tool)
    # DC auto-sources setup files. Capture known startup inputs without changing HOME.
    candidates = [Path.home()/'.synopsys_dc.setup']
    install = Path(data['site']['dc_shell']).parent.parent
    candidates.append(install/'admin/setup/.synopsys_dc.setup')
    if os.environ.get('SYNOPSYS'):
        candidates.append(Path(os.environ['SYNOPSYS'])/'admin/setup/.synopsys_dc.setup')
    for path in candidates:
        if path.is_file():
            external[str(path.resolve())] = sha(path)
    manifest = {'schema': 1, 'run': str(run), 'created_utc': datetime.now(timezone.utc).isoformat(),
                'git_head': git('rev-parse', 'HEAD').strip(), 'config': data,
                'scope': 'Core + adapters + Arbiter; observation ports retained; IFQ_DEPTH=2; PC_RST=0x80000000',
                'environment': {'SYNOPSYS': os.environ.get('SYNOPSYS', ''), 'dc_startup': 'installation + user setups; launch cwd is isolated', 'pt_startup': '-no_init'},
                'inputs': {str(p.relative_to(run)): sha(p) for p in (run/'inputs').rglob('*') if p.is_file()},
                'external_inputs': external, 'stages': {}, 'signoff': 'NOT_EVALUATED'}
    save(run/'manifest.json', manifest)
    return run


def clean_run(run_root, run_id):
    """显式删除一个已识别的 run；不加载 site，也不要求失败快照 hash 完整。"""
    require(run_id and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', run_id),
            'clean requires one valid RUN_ID (no paths or wildcards)')
    run = Path(run_root).resolve()/run_id
    require(not run.is_symlink(), f'Refusing to clean a symlink: {run}')
    if not run.exists():
        print(f'CLEAN_SKIP: run does not exist: {run}')
        return
    manifest = run/'manifest.json'
    require(manifest.is_file() and not manifest.is_symlink(), f'Refusing to clean an unrecognized directory: {run}')
    m = json.loads(manifest.read_text())
    require(isinstance(m, dict) and m.get('schema') == 1 and m.get('run') == str(run),
            'Refusing to clean a wrong/moved run manifest')
    stages = m.get('stages')
    require(isinstance(stages, dict) and all(isinstance(s, dict) for s in stages.values()), 'Invalid run stages')
    require(all(s.get('status') != 'RUNNING' for s in stages.values()),
            'Refusing to clean a RUNNING stage; stop/reconcile the tool process first')
    # rmtree does not follow child symlinks. Inputs (including DB) outside this run survive.
    shutil.rmtree(run)
    print(f'CLEANED: {run}')


# 核对输入和已完成阶段的产物是否仍与 manifest 一致，拒绝“名字一样就复用”。
# 内部输入使用 run 相对路径，外部库/工具使用绝对路径；run 不允许被静默搬迁。
# hash 用于实验追溯和意外修改检测，不是防恶意篡改的签名。
def verify(run):
    require((run/'manifest.json').is_file(), f'Missing run manifest: {run}')
    m = json.loads((run/'manifest.json').read_text())
    require(m.get('schema') == 1 and m.get('run') == str(run), 'Wrong/moved run manifest; do not silently rebase')
    for name, digest in {**m['inputs'], **m['external_inputs']}.items():
        path = run/name
        require(path.is_file() and sha(path) == digest, f'Input hash mismatch/missing: {path}')
    for stage in m['stages'].values():
        for name, digest in stage.get('artifacts', {}).items():
            path = run/name
            require(path.is_file() and sha(path) == digest, f'Artifact hash mismatch/missing: {path}')
    return m


# 03_sta/run.tcl 输出简单 TSV，避免从人读的长路径报告里猜测数值。
# WNS/TNS 是负裕量指标，零代表未收集到违例；不是时序覆盖已完整的证据。
def parse_metrics(path):
    values = dict(line.split('\t') for line in path.read_text().splitlines())
    require(set(values) == {'wns', 'tns', 'violating_endpoints'}, f'Malformed metrics: {path}')
    result = {k: float(v) for k,v in values.items()}
    require(all(math.isfinite(v) for v in result.values()), 'Non-finite timing metrics')
    require(result['wns'] <= 0 and result['tns'] <= result['wns'] and result['violating_endpoints'] >= 0 and result['violating_endpoints'].is_integer(), 'Inconsistent timing metrics')
    require((result['violating_endpoints'] == 0) == (result['wns'] == 0 and result['tns'] == 0), 'Timing counts disagree with negative slack')
    return result


# 把“进程退出”和“本阶段交付物有效”分开检查。只有所需文件非空、标记正确、
# 没有主流程 Error 等条件满足后，才能称执行 COMPLETE；仍不自动称 signoff PASS。
def inspect_stage(run, stage):
    report = run/'reports'/stage
    required = ['environment/version.rpt', 'complete.txt']
    if stage == 'syn':
        required += ['area/area.rpt', 'summary/qor.rpt', 'checks/check_design_pre.rpt', 'checks/check_design_post.rpt', 'checks/check_timing.rpt', 'checks/constraint_violations.rpt', 'timing/timing_max.rpt', 'timing/timing_min.rpt', 'environment/design.rpt', 'area/references.rpt', 'area/resources.rpt', 'power/power_status.txt']
        required += ['checks/high_fanout.rpt']
    elif stage == 'sta':
        required += ['environment/units.rpt', 'environment/design.rpt', 'environment/wire_load.rpt', 'checks/check_timing.rpt', 'checks/coverage.rpt', 'checks/coverage_untested.rpt', 'checks/constraint_violations.rpt', 'timing/timing_max.rpt', 'timing/timing_min.rpt', 'timing/metrics_max.tsv', 'timing/metrics_min.tsv']
        required += [f'timing/{group}_{delay}.rpt' for group in ['Reg2Reg', 'In2Reg', 'Reg2Out', 'In2Out'] for delay in ['max', 'min']]
        required += ['checks/disable_timing.rpt']
    required_paths = [report/name for name in required]
    libs = list((report/'environment').glob('library_*.rpt'))
    require(libs, 'Missing library reports')
    required_paths += libs
    if stage == 'syn':
        required_paths += [run/'outputs'/name for name in ['core.v', 'core.ddc', 'dc.sdc']]
    for path in required_paths:
        require(path.is_file() and path.stat().st_size > 0, f'Missing/empty output: {path}')
    require((report/'complete.txt').read_text().strip() == f'NPC_FLOW_COMPLETE {stage}', 'Missing completion sentinel')
    log = run/'logs'/f'{stage}.log'
    text = log.read_text(errors='replace')
    # Only the optional power region may contain non-blocking tool errors.
    # Its complete raw log/report remains archived and power stays unvalidated.
    if stage == 'syn':
        text = re.sub(r'(?ms)^NPC_OPTIONAL_POWER_BEGIN\n.*?^NPC_OPTIONAL_POWER_END\n', '', text)
    for path in required_paths:
        if path.suffix in ('.rpt', '.txt'):
            text += '\n'+path.read_text(errors='replace')
    require(not re.search(r'(?mi)^\s*(?:Error:|Fatal:|NPC_FLOW_ERROR:)', text), 'Tool/structural error in logs or reports (see run directory)')
    # 收集 warning 给 S3 人工处置，而不是只看 WNS。untested 检查可能来自常量、
    # 缺时钟或例外，必须结合 coverage_untested/check_timing 说明其合理性。
    result = {'execution': 'COMPLETE', 'signoff': 'REVIEW_REQUIRED', 'warnings': sorted(set(re.findall(r'(?m)^\s*Warning:.*$', text)))}
    if stage in ('syn', 'sta'):
        # 原始报告中的违例行数，包含电气和时序约束，不能当作去重 timing 端点数。
        # 兼容 (VIOLATED) 与 (VIOLATED: increase significant digits)。
        # 零行仍需人工核对报告/覆盖率，不据此自动宣告约束 PASS。
        violations = (report/'checks/constraint_violations.rpt').read_text()
        result['reported_constraint_violation_rows'] = len(re.findall(r'\(VIOLATED\b', violations))
        if result['reported_constraint_violation_rows']:
            result['signoff'] = 'CONSTRAINT_FAIL'
    if stage == 'syn':
        # 提取的是映射 cell area；其单位来自库，不是芯片/die 面积。
        # 正面积与合法 top 只是必要条件，不能替代资源保留和电路功能审查。
        area = re.search(r'Total cell area:\s*([0-9.eE+-]+)', (report/'area/area.rpt').read_text())
        require(area and math.isfinite(float(area[1])) and float(area[1]) > 0, 'Missing/zero/invalid mapped cell area')
        netlist = (run/'outputs/core.v').read_text()
        require(re.search(r'\bmodule\s+ysyx_core_axi4lite\b', netlist), 'Netlist top absent')
        require(not re.search(r'\b(?:GTECH_\w*|SEQGEN)\b', netlist), 'Unmapped primitive in exported netlist')
        result['cell_area'] = float(area[1])
        result['power'] = (report/'power/power_status.txt').read_text().strip()
    if stage == 'sta':
        # coverage 统计的是 timing checks，不是唯一端点数：一个端点可有多种检查。
        # 这里要求已知报告格式；遇到新版本格式要调整解析器，不能默认填零通过。
        result['timing'] = {d: parse_metrics(report/f'timing/metrics_{d}.tsv') for d in ['max', 'min']}
        # UG L-2016.06 PDF 657. Unknown report format fails closed.
        coverage = re.search(r'All Checks\s+(\d+)\s+(\d+)\s*\([^)]*\)\s+(\d+)\s*\([^)]*\)\s+(\d+)\s*\([^)]*\)', (report/'checks/coverage.rpt').read_text())
        require(coverage and int(coverage[1]) > 0, 'Missing/empty/unrecognized coverage summary')
        result['coverage'] = dict(zip(['total', 'met', 'violated', 'untested'], map(int, coverage.groups())))
        require(result['coverage']['total'] == sum(result['coverage'][k] for k in ['met','violated','untested']), 'Inconsistent coverage summary')
        if any(m['wns'] < 0 for m in result['timing'].values()) or result['coverage']['violated']:
            result['signoff'] = 'TIMING_FAIL'
        # Untested/constant checks and all structural warnings require disposition.
        # The driver never turns a clean shell exit or zero WNS into signoff PASS.
    return result


# 唯一 EDA 进程启动入口：先验证快照，再验证阶段依赖，最后按 argv 调工具。
# 不通过 shell 拼命令，工具路径可包含空格；stdout/stderr 合并保留完整诊断。
def execute(run, stage):
    m = verify(run)
    # runner 本身也属于实验输入。即便只修改注释，hash 也会变化；继续旧 run 时
    # 应调用其 inputs/npc/flow/01_common/flow.py，而不是悄悄套用当前工作区版本。
    require(sha(Path(__file__)) == sha(run/'inputs/npc/flow/01_common/flow.py'), 'Runner changed; invoke the archived runner for this run')
    require(stage not in m['stages'], f'Stage already attempted: {stage}; use a new run')
    if stage == 'sta':
        require(m['stages'].get('syn', {}).get('status') == 'COMPLETE', 'STA requires successful synthesis from this run')
        inspect_stage(run, 'syn')
    snapshot = run/'inputs/npc/flow'
    entry = snapshot/('03_sta/run.tcl' if stage == 'sta' else '02_syn/probe.tcl' if stage == 'probe' else '02_syn/run.tcl')
    tool = m['config']['site']['pt_shell' if stage == 'sta' else 'dc_shell']
    # PT -no_init 跳过安装/用户/当前目录的 setup（PT UG PDF 52）。
    # DC 仍可能加载安装/用户 setup，因此在 create_run 中记录已发现的依赖。
    argv = [tool] + (['-no_init'] if stage == 'sta' else []) + ['-f', str(entry)]
    env = dict(os.environ, NPC_RUN_CONFIG=str(run/'inputs/run.tcl'), NPC_FLOW_SNAPSHOT=str(snapshot), NPC_STAGE=stage)
    # 启动前先记 RUNNING；中途被终止留下的记录不会被误当成从未执行的新阶段。
    record = {'argv': argv, 'status': 'RUNNING'}
    m['stages'][stage] = record
    save(run/'manifest.json', m)
    try:
        with (run/'logs'/f'{stage}.log').open('w') as log:
            proc = subprocess.run(argv, cwd=run/'launch', env=env, stdout=log, stderr=subprocess.STDOUT)
        record['exit_code'] = proc.returncode
        require(proc.returncode == 0, f'{stage} exited {proc.returncode}; see {run}/logs/{stage}.log')
        # Reject changes made to library/config inputs during execution as well.
        verify(run)
        record['result'] = inspect_stage(run, stage)
        record['status'] = 'COMPLETE'
    except (FlowError, OSError, KeyboardInterrupt) as error:
        record['status'] = 'FAILED'
        record['failure'] = str(error)
        raise
    # 成功或失败都保留已产生的日志/报告/hash，便于诊断；不删除失败证据。
    finally:
        # Reports are categorized: hash nested files too, including failed/optional attempts.
        paths = list((run/'reports'/stage).rglob('*')) + [run/'logs'/f'{stage}.log']
        if stage == 'syn':
            paths += list((run/'outputs').glob('*'))
        record['artifacts'] = {str(p.relative_to(run)): sha(p) for p in paths if p.is_file()}
        save(run/'manifest.json', m)
    print(f'{stage}: COMPLETE; {record["result"]["signoff"]}; {run}')


# CLI 分两类：check/preflight 不创建 run；probe/synth/all 创建新 run。
# sta/inspect 仅接受已有 RUN，配置取自其 manifest，不混用当前 site。
# 返回码表示编排/产物检查结果；负 slack 可以正常归档，评价看 TIMING_FAIL 字段。
def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'preflight', 'probe', 'synth', 'sta', 'all', 'inspect', 'clean'])
    parser.add_argument('--config', type=Path, default=FLOW/'00_indata/configs/npc_core.tcl')
    parser.add_argument('--site', type=Path, default=FLOW/'00_indata/configs/site.example.tcl')
    parser.add_argument('--run-root', type=Path, default=FLOW/'build')
    parser.add_argument('--run-id')
    parser.add_argument('--run', type=Path)
    args = parser.parse_args(argv)
    try:
        if args.action == 'clean':
            require(args.run is None, 'clean uses RUN_ID and RUN_ROOT, not RUN')
            clean_run(args.run_root, args.run_id)
            return 0
        if args.action in ('sta', 'inspect'):
            require(args.run is not None, '--run is required')
            run = args.run.resolve()
            m = verify(run)
            if args.action == 'sta':
                execute(run, 'sta')
            else:
                # Report layout/parser belong to the frozen run, just like STA inputs.
                require(sha(Path(__file__)) == sha(run/'inputs/npc/flow/01_common/flow.py'),
                        'Runner changed; invoke the archived runner for this run')
                require(m['stages'], 'No stage has run')
                for name, stage in m['stages'].items():
                    require(stage['status'] == 'COMPLETE', f'{name} is {stage["status"]}')
                    print(json.dumps({name: inspect_stage(run, name)}, indent=2))
            return 0
        if args.action == 'check':
            local_check(args.config.resolve(), args.site.resolve())
            return 0
        data, sources, files = preflight(args.config.resolve(), args.site.resolve(), server=True, probe=args.action == 'probe')
        if args.action == 'preflight':
            print('SERVER_INPUTS_PASS: paths/config only; tool startup/license and command semantics still require execution')
            return 0
        run = create_run(data, sources, files, args.config, args.site, args.run_root, args.run_id)
        print(f'RUN={run}', flush=True)
        execute(run, 'probe' if args.action == 'probe' else 'syn')
        if args.action == 'all':
            execute(run, 'sta')
        return 0
    except (FlowError, OSError, ValueError) as error:
        print(f'FLOW_FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
