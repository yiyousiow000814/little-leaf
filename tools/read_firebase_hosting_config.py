"""Capture the existing finalized Hosting release using exactly two GETs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from datetime import datetime, timezone
from deploy_firebase_hosting import Transport, release_head, SITE_PATH, VERSION_RE


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
    raw_config = json.dumps(version['config'], sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()
    record = {'schema_version': 1, 'status': 'read-only-hosting-baseline',
              'observed_at': datetime.now(timezone.utc).isoformat(),
              'workflow_run': os.environ.get('GITHUB_RUN_ID'),
              'workflow_attempt': os.environ.get('GITHUB_RUN_ATTEMPT'),
              'workflow_commit': os.environ.get('GITHUB_SHA'),
              'previous_release': previous['release'], 'previous_version': previous['version'],
              'config_sha256': hashlib.sha256(raw_config).hexdigest(),
              'complete_version': version, 'requests': api.paths,
              'mutation_performed': False, 'activation_authorized': False,
              'freshness_limit': 'Release current at first GET; reread before any later activation. No continuous or final activation eligibility claimed.'}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = capture(Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), args.output)
    print('Read-only Hosting baseline retained; configuration SHA-256 ' + result['config_sha256'])


if __name__ == '__main__':
    main()
