"""Verify compact gate inputs issued by the exact full-artifact producer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re


REQUIRED = {
    'current': ('engine-evidence/summary.json',
                'web-build/web/release-manifest.json', 'crazygames-stage.json'),
    'historical': ('old-engine-evidence/summary.json',
                   'old-web-build/web/release-manifest.json'),
}


def receipt(root, lane, env):
    keys = {
        'GITHUB_SHA': r'[0-9a-f]{40}',
        'GITHUB_RUN_ID': r'[1-9][0-9]*',
        'GITHUB_RUN_ATTEMPT': r'[1-9][0-9]*',
        'FULL_ARTIFACT_ID': r'[1-9][0-9]*',
        'FULL_ARTIFACT_DIGEST': r'[0-9a-f]{64}',
    }
    binding = {key: env.get(key, '') for key in keys}
    if env.get('GITHUB_EVENT_NAME') != 'pull_request' or not all(
        re.fullmatch(pattern, binding[key]) for key, pattern in keys.items()
    ):
        raise ValueError('Exact ordinary PR and original archive binding required')
    artifacts = {}
    for filename in REQUIRED[lane]:
        file = root / filename
        if not file.is_file() or file.is_symlink():
            raise ValueError(f'Mandatory compact evidence is not a regular file: {filename}')
        with file.open('rb') as stream:
            artifacts[filename] = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {'lane': lane, 'binding': binding, 'files': artifacts}


def transfer(root, lane, phase, env):
    data = receipt(root, lane, env)
    target = root / f'pr-gate-{lane}.json'
    if phase == 'record':
        with target.open('x') as stream:
            json.dump(data, stream, sort_keys=True)
    elif target.is_symlink() or not target.is_file() or json.loads(target.read_text()) != data:
        raise ValueError(f'{lane} compact evidence does not bind the original archive')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('record', 'verify'))
    parser.add_argument('lane', choices=REQUIRED)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    transfer(args.root, args.lane, args.phase, os.environ)
