"""Orchestration failure tests use a fake executable, never real DC/PT."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

# 测试阅读顺序：setUp 创建临时假库/工具 → new_run 冻结输入 → syn 执行假工具。
# 普通用例检查 Python 的失败处理；test_real_tcl_wiring_with_mock_commands 则进一步
# 执行真实 Tcl 脚本，用 04_tests/eda_mock.tcl 提供命令替身。两者均不调用实际 EDA。
# 所有产物位于临时目录，MOCK 标识用于避免与真实 PPA 证据混淆。
FLOW = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('npc_flow', FLOW/'01_common/flow.py')
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)

# Minimal report fixture for checking provenance/error handling, not an EDA model.
FAKE = '''#!/usr/bin/env python3
import os
from pathlib import Path
run=Path(os.environ['NPC_RUN_CONFIG']).parent.parent
stage=os.environ['NPC_STAGE']; r=run/'reports'/stage; r.mkdir(parents=True,exist_ok=True)
(r/'version.rpt').write_text('MOCK TOOL - NOT EDA\\n')
(r/'library_mock.rpt').write_text('MOCK LIBRARY\\n')
(r/'complete.txt').write_text('NPC_FLOW_COMPLETE '+stage+'\\n')
if stage=='syn':
 for name in ['qor','check_design_pre','check_design_post','check_timing','constraints','timing_max','timing_min','design','references','resources']:
  (r/(name+'.rpt')).write_text('MOCK REPORT\\n')
 (r/'area.rpt').write_text('Total cell area: 12.5\\n')
 (r/'power_status.txt').write_text('NOT_EVALUATED: disabled\\n')
 for name,content in [('core.v','module ysyx_core_axi4lite(); endmodule'),('core.ddc','MOCK DDC'),('dc.sdc','MOCK SDC')]:
  (run/'outputs'/name).write_text(content)
if stage=='sta':
 for name in ['units','design','wire_load','check_timing','coverage_untested','constraints','timing_max','timing_min']:
  (r/(name+'.rpt')).write_text('MOCK REPORT\\n')
 (r/'coverage.rpt').write_text('All Checks 10 10 (100%) 0 (0%) 0 (0%)\\n')
 for delay in ['max','min']:
  (r/('metrics_'+delay+'.tsv')).write_text('wns\\t0.0\\ntns\\t0.0\\nviolating_endpoints\\t0\\n')
  for group in ['Reg2Reg','In2Reg','Reg2Out','In2Out']:
   (r/(group+'_'+delay+'.rpt')).write_text('MOCK PATH REPORT\\n')
'''


class FlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='npc-flow-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root/'design.tcl'
        self.config.write_text((FLOW/'00_indata/configs/npc_core.tcl').read_text())
        self.db = self.root/'library with spaces.db'
        self.db.write_text('MOCK NOT A LIBRARY')
        self.tool = self.root/'fake tool'
        self.tool.write_text(FAKE)
        self.tool.chmod(0o755)
        self.site = self.root/'site.tcl'
        self.site.write_text((FLOW/'00_indata/configs/site.example.tcl').read_text()+f'''
dict set site target_db {f.tcl_word(self.db)}
dict set site dc_shell {f.tcl_word(self.tool)}
dict set site pt_shell {f.tcl_word(self.tool)}
dict set site operating_condition mock_tt
dict set site library_reviewed 1
''')

    def append_cfg(self, text):
        with self.config.open('a') as stream:
            stream.write('\n'+text+'\n')

    def append_site(self, text):
        with self.site.open('a') as stream:
            stream.write('\n'+text+'\n')

    def new_run(self, name='test'):
        data, sources, files = f.preflight(self.config, self.site, server=True)
        return f.create_run(data, sources, files, self.config, self.site, self.root/'runs', name)

    def syn(self):
        run = self.new_run()
        f.execute(run, 'syn')
        return run

    def test_local_contract(self):
        f.local_check(self.config, self.site)

    def test_snapshot_excludes_build_and_pdk(self):
        layout = self.root/'flow'
        for name in ['Makefile', '01_common/setup.tcl', 'build/old/inputs/run.tcl',
                     '00_indata/DB/vendor.tcl', '00_indata/configs/site.local.tcl']:
            p = layout/name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('MOCK')
        cfg = f.load_config(self.config, self.site)['cfg']
        with patch.object(f, 'FLOW', layout):
            _, files = f.source_inputs(cfg)
        self.assertIn(layout/'01_common/setup.tcl', files)
        self.assertNotIn(layout/'build/old/inputs/run.tcl', files)
        self.assertNotIn(layout/'00_indata/DB/vendor.tcl', files)
        self.assertNotIn(layout/'00_indata/configs/site.local.tcl', files)

    def test_clean_failed_run_and_reuse_id(self):
        sibling = self.new_run('keep')
        self.tool.write_text(FAKE+'\nprint("Error: injected")\n')
        run = self.new_run('retry')
        with self.assertRaises(f.FlowError):
            f.execute(run, 'probe')
        # Make target must not depend on valid site/tool paths and must preserve other inputs/runs.
        p = subprocess.run(['make', '-C', str(FLOW), 'clean', f'RUN_ROOT={run.parent}',
                            'RUN_ID=retry', 'SITE=missing.tcl'], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout+p.stderr)
        self.assertFalse(run.exists())
        self.assertTrue(sibling.exists())
        self.assertTrue(self.db.exists())
        self.tool.write_text(FAKE)
        again = self.new_run('retry')
        f.execute(again, 'probe')

    def test_clean_rejects_unsafe_targets(self):
        root = self.root/'runs'
        for name in [None, '', '.', '..', '../escape', '/tmp', '*']:
            with self.subTest(name=name), self.assertRaises(f.FlowError):
                f.clean_run(root, name)
        run = self.new_run()
        alias = root/'alias'
        alias.symlink_to(run, target_is_directory=True)
        with self.assertRaisesRegex(f.FlowError, 'symlink'):
            f.clean_run(root, 'alias')
        unknown = root/'unknown'
        unknown.mkdir()
        with self.assertRaisesRegex(f.FlowError, 'unrecognized'):
            f.clean_run(root, 'unknown')
        m = json.loads((run/'manifest.json').read_text())
        m['stages']['probe'] = {'status': 'RUNNING'}
        f.save(run/'manifest.json', m)
        with self.assertRaisesRegex(f.FlowError, 'RUNNING'):
            f.clean_run(root, 'test')
        m['stages'] = {}
        m['run'] = '/different/run'
        f.save(run/'manifest.json', m)
        with self.assertRaisesRegex(f.FlowError, 'wrong/moved'):
            f.clean_run(root, 'test')
        self.assertTrue(run.exists())
        f.clean_run(root, 'absent')  # A missing valid ID is an idempotent no-op.

    def test_missing_variable(self):
        self.append_cfg('dict unset cfg period')
        with self.assertRaisesRegex(f.FlowError, 'missing='):
            f.preflight(self.config, self.site)

    def test_wrong_top(self):
        self.append_cfg('dict set cfg top wrong')
        with self.assertRaisesRegex(f.FlowError, 'Wrong top'):
            f.preflight(self.config, self.site)

    def test_missing_sdc(self):
        self.append_cfg('dict set cfg sdc flow/00_indata/constraints/missing.sdc')
        with self.assertRaisesRegex(f.FlowError, 'Missing input'):
            f.preflight(self.config, self.site)

    def test_missing_filelist(self):
        self.append_cfg('dict set cfg filelist flow/00_indata/filelists/missing.f')
        with self.assertRaisesRegex(f.FlowError, 'Missing input'):
            f.preflight(self.config, self.site)

    def test_nonfinite_budget(self):
        self.append_cfg('dict set cfg period Inf')
        with self.assertRaises(f.FlowError):
            f.preflight(self.config, self.site)

    def test_bad_delay_order(self):
        self.append_cfg('dict set cfg input_min 9')
        with self.assertRaisesRegex(f.FlowError, 'delay budget'):
            f.preflight(self.config, self.site)

    def test_dpi_define_rejected(self):
        self.append_cfg('dict set cfg defines {SYNTHESIS NPC_SIM_DPI}')
        with self.assertRaisesRegex(f.FlowError, 'defines'):
            f.preflight(self.config, self.site)

    def test_missing_db_local_ok_server_fails(self):
        self.db.unlink()
        f.preflight(self.config, self.site)
        with self.assertRaisesRegex(f.FlowError, 'library unavailable'):
            f.preflight(self.config, self.site, server=True)

    def test_empty_library(self):
        self.append_site('dict set site target_db {}')
        with self.assertRaisesRegex(f.FlowError, 'Empty site'):
            f.preflight(self.config, self.site)

    def test_unreviewed_library(self):
        self.append_site('dict set site library_reviewed 0')
        with self.assertRaisesRegex(f.FlowError, 'Run probe'):
            f.preflight(self.config, self.site, server=True)
        f.preflight(self.config, self.site, server=True, probe=True)

    def test_missing_tool(self):
        self.append_site('dict set site pt_shell /missing/npc/pt_shell')
        with self.assertRaisesRegex(f.FlowError, 'executable unavailable'):
            f.preflight(self.config, self.site, server=True)

    def test_tool_symlink_dispatch(self):
        # A shared launcher can select the product from its invocation name.
        # Resolving dc_shell/pt_shell to the target before exec loses that name.
        self.tool.write_text(FAKE.replace(
            'import os\nfrom pathlib import Path\n',
            'import os,sys\nfrom pathlib import Path\n'
            'expected = "pt_shell" if os.environ["NPC_STAGE"] == "sta" else "dc_shell"\n'
            'if Path(sys.argv[0]).name != expected:\n'
            ' print("Error: The  script is not supported.")\n'
            ' raise SystemExit(1)\n'))
        for name in ['dc_shell', 'pt_shell']:
            link = self.root/name
            link.symlink_to(self.tool)
            self.append_site(f'dict set site {name} {f.tcl_word(link)}')
        run = self.new_run()
        for stage in ['probe', 'syn', 'sta']:
            f.execute(run, stage)
        manifest = f.verify(run)
        for stage, name in [('probe', 'dc_shell'), ('syn', 'dc_shell'), ('sta', 'pt_shell')]:
            self.assertEqual(manifest['stages'][stage]['argv'][0], str(self.root/name))
        # The invocation path is preserved, but hashing still reads target bytes.
        self.assertEqual(manifest['external_inputs'][str(self.root/'dc_shell')], f.sha(self.tool))

    def test_duplicate_run(self):
        self.new_run()
        with self.assertRaisesRegex(f.FlowError, 'Run already exists'):
            self.new_run()

    def test_sta_requires_synthesis(self):
        run = self.new_run()
        with self.assertRaisesRegex(f.FlowError, 'requires successful synthesis'):
            f.execute(run, 'sta')

    def test_changed_snapshot(self):
        run = self.new_run()
        (run/'inputs/npc/flow/00_indata/constraints/core.sdc').write_text('corrupt')
        with self.assertRaisesRegex(f.FlowError, 'hash mismatch'):
            f.execute(run, 'syn')

    def test_changed_library(self):
        run = self.new_run()
        self.db.write_text('different library')
        with self.assertRaisesRegex(f.FlowError, 'hash mismatch'):
            f.execute(run, 'syn')

    def test_changed_netlist(self):
        run = self.syn()
        (run/'outputs/core.v').write_text('old netlist')
        with self.assertRaisesRegex(f.FlowError, 'Artifact hash mismatch'):
            f.execute(run, 'sta')

    def test_stage_cannot_rerun(self):
        run = self.syn()
        with self.assertRaisesRegex(f.FlowError, 'already attempted'):
            f.execute(run, 'syn')

    def test_zero_exit_error_text(self):
        self.tool.write_text(FAKE+'\nprint("Error: injected link failure")\n')
        run = self.new_run()
        with self.assertRaisesRegex(f.FlowError, 'Tool/structural error'):
            f.execute(run, 'syn')
        self.assertEqual(json.loads((run/'manifest.json').read_text())['stages']['syn']['status'], 'FAILED')

    def test_nonzero_tool_exit(self):
        self.tool.write_text(FAKE+'\nraise SystemExit(7)\n')
        run = self.new_run()
        with self.assertRaisesRegex(f.FlowError, 'exited 7'):
            f.execute(run, 'syn')

    def test_missing_report_and_zero_area(self):
        run = self.syn()
        netlist = run/'outputs/core.v'
        original = netlist.read_text()
        netlist.write_text(original+'\nGTECH_AND2 unmapped();\n')
        with self.assertRaisesRegex(f.FlowError, 'Unmapped primitive'):
            f.inspect_stage(run, 'syn')
        netlist.write_text(original)
        report = run/'reports/syn/area.rpt'
        report.write_text('Total cell area: 0\n')
        with self.assertRaisesRegex(f.FlowError, 'cell area'):
            f.inspect_stage(run, 'syn')
        report.unlink()
        with self.assertRaisesRegex(f.FlowError, 'Missing/empty'):
            f.inspect_stage(run, 'syn')

    def test_missing_complete_marker(self):
        run = self.syn()
        (run/'reports/syn/complete.txt').write_text('wrong')
        with self.assertRaisesRegex(f.FlowError, 'completion sentinel'):
            f.inspect_stage(run, 'syn')

    def test_complete_is_not_signoff(self):
        run = self.syn()
        f.execute(run, 'sta')
        result = f.inspect_stage(run, 'sta')
        self.assertEqual(result['signoff'], 'REVIEW_REQUIRED')
        self.assertEqual(result['coverage']['total'], 10)

    def test_negative_slack_and_untested(self):
        run = self.syn()
        f.execute(run, 'sta')
        (run/'reports/sta/metrics_max.tsv').write_text('wns\t-1\ntns\t-2\nviolating_endpoints\t2\n')
        self.assertEqual(f.inspect_stage(run, 'sta')['signoff'], 'TIMING_FAIL')
        (run/'reports/sta/metrics_max.tsv').write_text('wns\t0\ntns\t0\nviolating_endpoints\t0\n')
        (run/'reports/sta/coverage.rpt').write_text('All Checks 10 9 (90%) 0 (0%) 1 (10%)\n')
        self.assertEqual(f.inspect_stage(run, 'sta')['signoff'], 'REVIEW_REQUIRED')

    def test_unknown_coverage_format(self):
        run = self.syn()
        f.execute(run, 'sta')
        (run/'reports/sta/coverage.rpt').write_text('Changed report format')
        with self.assertRaisesRegex(f.FlowError, 'unrecognized coverage'):
            f.inspect_stage(run, 'sta')

    def test_sdc_missing_output_min(self):
        broken = self.root/'broken.sdc'
        broken.write_text('\n'.join(line for line in (FLOW/'00_indata/constraints/core.sdc').read_text().splitlines() if not line.startswith('set_output_delay -clock core_clk -min')))
        p = subprocess.run(['tclsh', str(FLOW/'04_tests/sdc_check.tcl'), str(self.config), str(broken), str(f.NPC/'vsrc/top/ysyx_core_axi4lite.sv')], capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('Missing set_output_delay:-min', p.stderr)

    def test_real_tcl_wiring_with_mock_commands(self):
        self.append_cfg('dict set cfg power_enable 1')
        self.tool.write_text("#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\nmock=Path(os.environ['NPC_FLOW_SNAPSHOT'])/'04_tests/eda_mock.tcl'\nos.execvp('tclsh',['tclsh',str(mock),sys.argv[-1]])\n")
        probe = self.new_run('probe')
        f.execute(probe, 'probe')
        run = self.syn()
        f.execute(run, 'sta')
        for current, stage in [(probe, 'probe'), (run, 'syn'), (run, 'sta')]:
            reports = current/'reports'/stage
            self.assertIn('MOCK-VERSION-NOT-EDA', (reports/'version.rpt').read_text())
            if stage != 'sta':
                self.assertIn('MOCK synthetic library standard.sldb', (reports/'library_standard.sldb.rpt').read_text())
                self.assertIn('MOCK technology library gtech', (reports/'library_gtech.rpt').read_text())
            else:
                self.assertFalse((reports/'library_standard.sldb.rpt').exists())
        result = f.inspect_stage(run, 'sta')
        self.assertEqual(result['timing']['max']['violating_endpoints'], 1)
        self.assertEqual(result['timing']['max']['tns'], -1.0)
        self.assertEqual(result['signoff'], 'TIMING_FAIL')
        self.assertIn('NOT_EVALUATED', f.inspect_stage(run, 'syn')['power'])

    def test_probe_report_errors_despite_successful_exit(self):
        # 真实 DC 可能退出 0 且写 complete.txt，但 redirect 内的报告仍含 Error。
        for filename, diagnostic in [
            ('version.rpt', "Error: unknown command 'version' (CMD-005)"),
            ('library_standard.sldb.rpt', 'Error: Use the report_synlib command. (UIL-29)'),
        ]:
            with self.subTest(report=filename):
                self.tool.write_text(FAKE + f"\n(r/{filename!r}).write_text({diagnostic!r})\n")
                run = self.new_run(filename)
                with self.assertRaisesRegex(f.FlowError, 'Tool/structural error'):
                    f.execute(run, 'probe')
                stage = json.loads((run/'manifest.json').read_text())['stages']['probe']
                self.assertEqual(stage['exit_code'], 0)
                self.assertEqual(stage['status'], 'FAILED')

    def test_tcl_path_quoting(self):
        literal = 'space $env(HOME) [error bad] " \\ end'
        p = subprocess.run(['tclsh'], input='puts '+f.tcl_word(literal)+'\n', text=True, capture_output=True)
        self.assertEqual(p.stdout.rstrip('\n'), literal)


if __name__ == '__main__':
    unittest.main()
