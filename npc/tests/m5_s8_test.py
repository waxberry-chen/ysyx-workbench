#!/usr/bin/env python3
"""Rebuild M5 functional acceptance in a new, source-only local checkout.

No DC/PT invocation. Existing stage tests remain the acceptance oracles.
Git objects and installed tool/download caches may be reused; generated RTL,
Mill outputs, Verilator objects, reference .so and AM images are rebuilt.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def snapshot(source, target, records, patches):
    """Clone each populated repository locally, including recorded dirty patches."""
    head = git(source, 'rev-parse', 'HEAD').decode().strip()
    name = str(source.relative_to(ROOT))
    patch = git(source, 'diff', 'HEAD', '--binary', '--ignore-submodules=all')
    record = dict(head=head, status=git(source, 'status', '--short').decode(),
                  patch_sha256=hashlib.sha256(patch).hexdigest())
    records[name] = record
    subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-checkout',
                    str(source), str(target)], check=True)
    subprocess.run(['git', '-C', str(target), 'checkout', '--quiet', '--detach', head], check=True)
    if patch:
        patch_path = patches / (name.replace('/', '__').replace('.', 'root') + '.patch')
        patch_path.write_bytes(patch)
        subprocess.run(['git', '-C', str(target), 'apply', '--binary', '-'], input=patch, check=True)
    for item in git(target, 'ls-files', '--stage', '-z').split(b'\0'):
        if not item:
            continue
        meta, path = item.split(b'\t', 1)
        mode, revision, _ = meta.split()
        if mode != b'160000':
            continue
        child = path.decode()
        actual = git(source / child, 'rev-parse', 'HEAD').strip()
        if actual != revision:
            raise RuntimeError(f'Unrecorded submodule revision: {name}/{child}')
        snapshot(source / child, target / child, records, patches)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / 'npc/build/m5-s8')
    args = parser.parse_args()
    out = args.out.resolve()
    # Never clean an existing run: a failed attempt remains evidence.
    out.mkdir(parents=True, exist_ok=False)
    (out / 'logs').mkdir()
    (out / 'patches').mkdir()
    workspace = out / 'workspace'
    manifest = dict(status='RUNNING', source=str(ROOT), workspace=str(workspace),
                    repositories={}, commands=[], eda_rerun=False,
                    started=time.strftime('%Y-%m-%dT%H:%M:%S%z'))

    def save():
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

    save()
    try:
        snapshot(ROOT, workspace, manifest['repositories'], out / 'patches')
        # Both are independent, ignored repositories, not root gitlinks.
        for name in ('am-kernels', 'rt-thread-am'):
            snapshot(ROOT / name, workspace / name,
                     manifest['repositories'], out / 'patches')
        # Historical S3/S6 checks hash .config to prove it is left untouched.
        # The actual reference build uses tracked configs/ysyxsoc-ref.h.
        shutil.copy2(ROOT / 'nemu/.config', workspace / 'nemu/.config')
        manifest['nemu_config_sha256'] = sha(workspace / 'nemu/.config')
        # Reuse the installed firtool binary, not prior generated design files.
        firtool = Path('ysyxSoC/patch/firtool')
        shutil.copytree(ROOT / firtool, workspace / firtool)
        manifest['firtool_sha256'] = sha(workspace / firtool / 'firtool-1.105.0/bin/firtool')
        manifest['runner_sha256'] = sha(Path(__file__))
        manifest['clean_before_build'] = {
            p: not (workspace / p).exists() for p in (
                'npc/build', 'nemu/build', 'ysyxSoC/build', 'ysyxSoC/out',
                'abstract-machine/am/build', 'abstract-machine/klib/build')}
        assert all(manifest['clean_before_build'].values())
        env = dict(os.environ, AM_HOME=str(workspace / 'abstract-machine'),
                   NEMU_HOME=str(workspace / 'nemu'), NPC_HOME=str(workspace / 'npc'),
                   CCACHE_DISABLE='1')
        manifest['compiler_cache'] = 'disabled: compile objects from source'
        # Prevent an interactive shell's old workspace from redirecting Mill.
        env.pop('MILL_WORKSPACE_ROOT', None)
        steps = [
            ('soc-generation', ['make', '-C', 'ysyxSoC', 'verilog']),
            ('soc-contract', ['python3', 'npc/tests/ysyx_soc_contract_check.py']),
            ('simulators-and-reference', ['make', '-C', 'npc', 's6-build']),
            ('unit-and-elaboration', ['make', '-C', 'npc', 'lint', 'primitive-test',
                'ifu-test', 'lsu-test', 'exu-test', 'architectural-state-test',
                'idu-contract-test', 's1-elaboration-test']),
            ('s2-bringup', ['python3', 'npc/tests/m5_s2_test.py']),
            ('s3-runtime', ['python3', 'npc/tests/m5_s3_test.py']),
            ('s4-boot', ['python3', 'npc/tests/m5_s4_test.py', '--only', 'boot']),
            ('s4-capacity', ['python3', 'npc/tests/m5_s4_test.py', '--only', 'capacity']),
            ('s5-interrupt', ['python3', 'npc/tests/m5_s5_test.py']),
            ('delay-unit', ['make', '-C', 'npc', 's6-delay-test']),
            ('s6-system', ['python3', 'npc/tests/m5_s6_test.py']),
            ('flow-local', ['make', '-C', 'npc/flow', 'check', 'test', 'scope-check']),
        ]
        for name, command in steps:
            print(f'S8 {name}: running; log={out / "logs" / (name + ".log")}', flush=True)
            record = dict(name=name, command=command, status='RUNNING')
            manifest['commands'].append(record)
            save()
            start = time.monotonic()
            with (out / 'logs' / f'{name}.log').open('w') as log:
                result = subprocess.run(command, cwd=workspace, env=env,
                                        stdout=log, stderr=subprocess.STDOUT)
            record.update(returncode=result.returncode,
                          wall_seconds=round(time.monotonic() - start, 3),
                          status='PASS' if result.returncode == 0 else 'FAIL')
            save()
            if result.returncode:
                raise RuntimeError(f'{name}: exit {result.returncode}; inspect its log')
            print(f'S8 {name}: PASS ({record["wall_seconds"]} s)', flush=True)
        manifest['status'] = 'PASS'
    except BaseException as error:
        manifest.update(status='FAIL', error=str(error))
        raise
    finally:
        manifest['finished'] = time.strftime('%Y-%m-%dT%H:%M:%S%z')
        save()
    print(f'S8 clean functional reproduction: PASS; {out}', flush=True)


if __name__ == '__main__':
    main()
