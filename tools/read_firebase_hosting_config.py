"""Capture the existing finalized Hosting release using exactly two GETs."""
import argparse
import copy
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from datetime import datetime, timezone
from deploy_firebase_hosting import Transport, release_head, SITE_PATH, VERSION_RE


FIXED_FRAME_CSP = 'frame-ancestors https://html-classic.itch.zone https://siowyiyou.itch.io'
FIXED_ADDITIONS = [
    {'glob': path, 'headers': {'Content-Security-Policy': FIXED_FRAME_CSP, 'Cache-Control': 'no-cache'}}
    for path in ['/itch/', '/itch/index.html']
] + [{'glob': '/itch/hosting-release.json', 'headers': {'Cache-Control': 'no-store'}}]


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                   ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def fixed_checks(config):
    rows = config.get('headers', [])
    if not isinstance(rows, list):
        raise ValueError('Header structure required')
    unknown = []
    recognized = 0
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get('headers'), dict):
            unknown.append(row)
            continue
        # Recognize only the complete, fixed proposed rows, never arbitrary
        # globs or values. Recognition is not effective Hosting match proof.
        if row in FIXED_ADDITIONS:
            recognized += 1
        elif any(not isinstance(key, str) or key.lower() in {
                'content-security-policy', 'content-security-policy-report-only',
                'x-frame-options', 'cache-control'} for key in row['headers']):
            unknown.append(row)
    proposed = copy.deepcopy(config)
    proposed['headers'] = copy.deepcopy(rows) + copy.deepcopy(FIXED_ADDITIONS)
    assert proposed['headers'][:len(rows)] == rows
    assert {k: v for k, v in proposed.items() if k != 'headers'} == {
        k: v for k, v in config.items() if k != 'headers'}
    return {'proposal_id': 'same-itch-fixed-three-header-append-v1',
            'proposed_config_sha256': digest(proposed),
            'all_existing_headers_preserved': True, 'all_other_fields_preserved': True,
            'recognized_fixed_header_rows': recognized,
            'unknown_relevant_header_rows': len(unknown),
            'unknown_relevant_header_rows_sha256': digest(unknown),
            'framing_status': 'HOLD-unknown-header-rules' if unknown else 'not-effectively-verified',
            'effective_framing_verified': False}


def workflow_identity(name, pattern):
    value = os.environ.get(name)
    if value is not None and not re.fullmatch(pattern, value):
        raise ValueError('Workflow identity format required')
    return value


def capture(transport, output):
    class TwoGets:
        def __init__(self):
            self.paths = []

        def request(self, method, path):
            if method != 'GET' or len(self.paths) >= 2:
                raise ValueError('Read-only request boundary')
            if not self.paths:
                if path != SITE_PATH + '/releases?pageSize=1':
                    raise ValueError('Fixed release read required')
            elif not VERSION_RE.fullmatch(path):
                raise ValueError('Fixed-site version read required')
            self.paths.append(path)
            return transport.request('GET', path)

    api = TwoGets()
    previous = release_head(api)
    if previous is None:
        raise ValueError('Existing release required')
    version = api.request('GET', previous['version'])
    if version.get('name') != previous['version'] or version.get('status') != 'FINALIZED' or not isinstance(version.get('config'), dict):
        raise ValueError('Exact finalized existing configuration required')
    record = {'schema_version': 2, 'status': 'read-only-hosting-allowlisted-summary',
              'observed_at': datetime.now(timezone.utc).isoformat(),
              'workflow_run': workflow_identity('GITHUB_RUN_ID', r'[1-9][0-9]*'),
              'workflow_attempt': workflow_identity('GITHUB_RUN_ATTEMPT', r'[1-9][0-9]*'),
              'workflow_commit': workflow_identity('GITHUB_SHA', r'[0-9a-f]{40}'),
              'previous_release': previous['release'], 'previous_version': previous['version'],
              'config_sha256': digest(version['config']),
              'fixed_checks': fixed_checks(version['config']),
              'mutation_performed': False, 'activation_authorized': False,
              'freshness_limit': 'Release current at first GET; reread before any later activation. No continuous or final activation eligibility claimed.'}
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError('Fresh summary destination required')
    output.write_text(json.dumps(record, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = capture(Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), args.output)
    print('Read-only allowlisted Hosting summary retained; activation remains unapproved')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Read-only Hosting summary failed; raw response omitted', file=sys.stderr)
        raise SystemExit(1) from None
