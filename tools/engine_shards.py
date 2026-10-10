"""Balance complete engine coverage; merge only same-source, complete shard reports."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
STAFF = ['empty-profile', 'fresh', 'saved-load', 'standalone-load', 'bad-load']


def suite_names():
    spec = importlib.util.spec_from_file_location('integration_suite', ROOT / 'tests/run_integration_candidate.py')
    suite = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(suite)
    names = [name for name, _ in suite.SUITES]
    if len(names) != len(set(names)):
        raise ValueError('Duplicate canonical suite')
    return names + ['staff-start']


def plan(count, names=None, timing=None):
    if count < 1 or count > 5:
        raise ValueError('Use between one and five independent engine runners')
    names = suite_names() if names is None else names
    timing = json.loads(Path(__file__).with_name('engine_suite_times.json').read_text())['seconds'] if timing is None else timing
    shards = [[] for _ in range(count)]
    loads = [0.0] * count
    for name in sorted(names, key=lambda name: (-timing.get(name, 5.0), name)):
        index = min(range(count), key=lambda i: (loads[i], i))
        shards[index].append(name)
        loads[index] += timing.get(name, 5.0)
    return shards


def expected_records(names):
    return {name for name in names if name != 'staff-start'} | (
        {'staff-start-' + case for case in STAFF} if 'staff-start' in names else set())


def merge_reports(paths, count, source, output):
    assignments = plan(count)
    if len(paths) != count:
        raise ValueError('All shard reports are mandatory')
    reports = [json.loads(path.read_text()) for path in paths]
    seen, records, source_hashes = set(), [], None
    for report in reports:
        shard = report.get('shard', {})
        index = shard.get('index')
        if not isinstance(index, int) or index not in range(count) or index in seen:
            raise ValueError('Duplicate or unexpected shard')
        seen.add(index)
        if shard.get('count') != count or shard.get('suites') != assignments[index]:
            raise ValueError('Shard assignment differs from canonical coverage')
        if report.get('status') != 'passed' or report.get('source_commit') != source or report.get('player_save_used') is not False:
            raise ValueError('Shard must pass on exact source without player saves')
        if report.get('workflow_run') != os.environ.get('GITHUB_RUN_ID', 'local') or report.get('workflow_attempt') != os.environ.get('GITHUB_RUN_ATTEMPT', 'local'):
            raise ValueError('Shard evidence must come from this run and attempt')
        hashes = report.get('source_sha256')
        if not hashes or (source_hashes is not None and source_hashes != hashes):
            raise ValueError('Shard source bytes differ')
        source_hashes = hashes
        rows = report.get('records', [])
        expected = expected_records(assignments[index]) | {'import'}
        if len(rows) != len(expected) or {r['test'] for r in rows} != expected:
            raise ValueError('Missing or duplicate suite record')
        if report.get('total_checks') != sum(r['checks'] for r in rows):
            raise ValueError('Shard assertion totals differ')
        if any(r['exit_code'] or r['failures'] for r in rows):
            raise ValueError('Failed suite cannot be merged')
        known = {'test_autosave_feedback_adversarial': {
            "ERROR: Parse JSON failed. Error at line 0: Expected 'true', 'false', or 'null', got 'not'"}}
        if any('ERROR:' in line and line not in known.get(r['test'], set())
               for r in rows for line in r['diagnostics']):
            raise ValueError('Engine diagnostics cannot be hidden by shard aggregation')
        for record in rows:
            if record['test'] == 'import' and index != 0:
                continue
            records.append(record)
    if len(records) != len(expected_records(suite_names())) + 1:
        raise ValueError('Complete engine coverage is required')
    # Preserve the complete-gate schema used by build_web.py. That exporter still
    # validates every canonical record and diagnostics before creating any export.
    merged = dict(reports[0])
    merged.pop('shard')
    merged.update(records=sorted(records, key=lambda r: r['test']),
                  total_checks=sum(r['checks'] for r in records),
                  test_processes=len(records) - 1,
                  disposable_fixture_retained=any(r.get('disposable_fixture_retained', True) for r in reports))
    output.mkdir(parents=True, exist_ok=False)
    (output / 'summary.json').write_text(json.dumps(merged, indent=2) + '\n')
    for path in paths:
        for file in path.parent.iterdir():
            if file.name == 'summary.json' or not file.is_file():
                continue
            target = output / file.name
            if target.exists():
                # Imports are independent and retained under their shard identity.
                if file.name == 'import.log':
                    target = output / (path.parent.name + '-import.log')
                else:
                    raise ValueError('Duplicate derived evidence: ' + file.name)
            shutil.copy2(file, target)
    return merged


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['run', 'merge'])
    parser.add_argument('--count', type=int, default=5)
    parser.add_argument('--shard', type=int)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reports', type=Path)
    args = parser.parse_args()
    if args.action == 'run':
        assignments = plan(args.count)
        if args.shard not in range(args.count):
            parser.error('Valid shard index required')
        subprocess.run([sys.executable, str(ROOT / 'tests/run_integration_candidate.py'),
                        '--unpaced-ui', '--only', *assignments[args.shard], '--output', str(args.output),
                        '--lock', str(args.output.with_suffix('.lock'))], check=True)
        path = args.output / 'summary.json'
        report = json.loads(path.read_text())
        report.update(shard={'index': args.shard, 'count': args.count, 'suites': assignments[args.shard]},
                      workflow_run=os.environ.get('GITHUB_RUN_ID', 'local'),
                      workflow_attempt=os.environ.get('GITHUB_RUN_ATTEMPT', 'local'))
        path.write_text(json.dumps(report, indent=2) + '\n')
    else:
        source = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
        merge_reports(sorted(args.reports.glob('*/summary.json')), args.count, source, args.output)


if __name__ == '__main__':
    main()
