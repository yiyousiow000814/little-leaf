"""Bind the source-only Chrome lane's receipt bundle to this exact consuming attempt."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from qualification.run_firebase_focused import COMMANDS

GATES = ('adapter.log', 'delayed-network.log', 'recovery.log', 'choice.log', 'session.log',
         'update-notice.log', 'recovery-presentation.log', 'recovery-browser.log')


def verify(folder, commit, tree, run_id, attempt):
    if not all([commit, tree, run_id, attempt]):
        raise ValueError("Missing current source or Actions identity")
    for name in GATES:
        data = (folder / name).read_bytes()
        info = json.loads((folder / (name + '.json')).read_text())
        identity = (info.get('source_commit'), info.get('source_tree'),
                    info.get('workflow_run'), info.get('workflow_attempt'))
        if (not data or identity != (commit, tree, run_id, attempt)
                or info.get('schema_version') != 1 or info.get('status') != 'passed'
                or info.get('exit_code') != 0 or info.get('command') != COMMANDS[name]
                or info.get('log_sha256') != hashlib.sha256(data).hexdigest()):
            raise ValueError(f"Invalid or stale source recovery receipt: {name}")
    grid = json.loads((folder / 'pre-grid-archive-browser.json').read_text())
    if (grid.get('passed') is not True or grid.get('real_indexeddb') is not True
            or grid.get('synthetic_cloud') is not True or grid.get('player_saves_used') is not False
            or not isinstance(grid.get('checks'), list) or not grid['checks']
            or grid.get('total_checks') != len(grid['checks'])):
        raise ValueError("Incomplete real IndexedDB grid receipt")


if __name__ == '__main__':
    git = lambda ref: subprocess.check_output(['git', 'rev-parse', ref], text=True).strip()
    commit = git('HEAD')
    if commit != os.environ['GITHUB_SHA']:
        raise SystemExit("Source checkout differs from workflow commit")
    verify(Path(sys.argv[1]), commit, git('HEAD^{tree}'), os.environ['GITHUB_RUN_ID'], os.environ['GITHUB_RUN_ATTEMPT'])
