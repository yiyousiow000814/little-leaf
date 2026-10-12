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
if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from release.deploy_firebase_hosting import Transport, release_head, SITE_PATH, VERSION_RE


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


TARGET_PATHS = ('/', '/itch/', '/itch/index.html', '/itch/hosting-release.json')
HEADER_FAMILIES = {'content-security-policy': 'CSP',
                   'content-security-policy-report-only': 'CSP_REPORT_ONLY',
                   'x-frame-options': 'XFO', 'cache-control': 'CACHE_CONTROL'}


def path_match(row, path):
    """A finite pattern registry; unsupported Bash/RE2 syntax stays unknown."""
    if 'regex' in row:
        return 'RE2_UNSUPPORTED', 'unknown'
    glob = row.get('glob')
    if not isinstance(glob, str):
        return 'MALFORMED_PATTERN', 'unknown'
    if glob in {'**', '/**'}:
        return 'GLOBAL_GLOBSTAR', 'yes'
    if glob in {'/itch/**', 'itch/**'}:
        return 'ITCH_SUBTREE_GLOBSTAR', 'yes' if path.startswith('/itch/') else 'no'
    # Exact common suffix globs only; these have no exclusions or extglob.
    for extension in ('html', 'js', 'css', 'wasm', 'pck', 'json'):
        if glob in {'**/*.' + extension, '/**/*.' + extension}:
            return 'SUFFIX_' + extension.upper(), 'yes' if path.endswith('.' + extension) else 'no'
    if glob.startswith('/') and not any(c in glob for c in '*?[]{}()!\\'):
        return 'ABSOLUTE_LITERAL', 'yes' if glob == path else 'no'
    if any(c in glob for c in '()'):
        return 'EXTGLOB_UNSUPPORTED', 'unknown'
    if any(c in glob for c in '{}'):
        return 'BRACE_GLOB_UNSUPPORTED', 'unknown'
    if any(c in glob for c in '?[]!'):
        return 'SPECIAL_GLOB_UNSUPPORTED', 'unknown'
    return 'OTHER_GLOB_UNSUPPORTED', 'unknown'


def value_token(family, value):
    """Return predefined categories, never source strings or fragments."""
    if not isinstance(value, str):
        return 'MALFORMED_VALUE', False
    constants = {'CSP': {FIXED_FRAME_CSP: 'ITCH_ANCESTORS_EXACT',
                         "frame-ancestors 'none'": 'CSP_NONE_EXACT',
                         "frame-ancestors 'self'": 'CSP_SELF_EXACT'},
                 'XFO': {'DENY': 'XFO_DENY_EXACT', 'SAMEORIGIN': 'XFO_SAMEORIGIN_EXACT'},
                 'CACHE_CONTROL': {'no-cache': 'CACHE_NO_CACHE_EXACT',
                                   'no-store': 'CACHE_NO_STORE_EXACT',
                                   'max-age=3600': 'CACHE_MAX_AGE_3600_EXACT'}}
    if value in constants.get(family, {}):
        return constants[family][value], True
    if family in {'CSP', 'CSP_REPORT_ONLY'}:
        directives = [part.strip().split(None, 1)[0].lower()
                      for part in value.split(';') if part.strip()]
        return ('CSP_HAS_UNRECOGNIZED_FRAME_ANCESTORS' if 'frame-ancestors' in directives
                else 'CSP_NO_FRAME_ANCESTORS_TOKEN'), False
    if family == 'XFO':
        return 'XFO_NONSTANDARD_VALUE', False
    return 'CACHE_OTHER_VALUE', False


def effective_diagnosis(config):
    rows = config.get('headers', [])
    if not isinstance(rows, list):
        raise ValueError('Header structure required')
    scenarios = {}
    for scenario, scenario_rows in [('baseline', rows), ('fixed_append', rows + FIXED_ADDITIONS)]:
        paths = {}
        for path in TARGET_PATHS:
            trace, holds, applicable = [], set(), {}
            for index, row in enumerate(scenario_rows):
                if not isinstance(row, dict) or not isinstance(row.get('headers'), dict):
                    trace.append({'row_index': index, 'row_sha256': digest(row),
                                  'pattern': 'MALFORMED_ROW', 'match': 'unknown', 'headers': []})
                    holds.add('MALFORMED_ROW')
                    continue
                relevant = [(HEADER_FAMILIES[key.lower()], value) for key, value in row['headers'].items()
                            if isinstance(key, str) and key.lower() in HEADER_FAMILIES]
                if not relevant:
                    continue
                pattern, match = path_match(row, path)
                headers = []
                for family, value in relevant:
                    token, known = value_token(family, value)
                    headers.append({'family': family, 'value_token': token})
                    if match == 'unknown':
                        holds.add('UNSUPPORTED_PATTERN')
                    if match != 'no' and not known:
                        holds.add('UNRECOGNIZED_VALUE')
                    if match == 'yes':
                        applicable.setdefault(family, []).append(token)
                        if family != 'CSP_REPORT_ONLY' and token in {
                                'CSP_NONE_EXACT', 'CSP_SELF_EXACT', 'XFO_DENY_EXACT', 'XFO_SAMEORIGIN_EXACT'}:
                            holds.add('RECOGNIZED_FRAME_BLOCKER')
                trace.append({'row_index': index, 'row_sha256': digest(row),
                              'pattern': pattern, 'match': match, 'headers': headers})
            if any(len(values) > 1 for values in applicable.values()):
                holds.add('OVERLAPPING_FAMILY_RESOLUTION_UNVERIFIED')
            paths[path] = {'ordered_rules': trace, 'applicable_tokens': applicable,
                           'hold_categories': sorted(holds),
                           'status': 'HOLD' if holds else 'CLASSIFIED_NOT_EFFECTIVELY_VERIFIED'}
        scenarios[scenario] = paths
    return {'schema_version': 1, 'matching_scope': 'finite-reviewed-pattern-registry-initial-request-path',
            'scenarios': scenarios, 'effective_framing_verified': False,
            'browser_or_hosted_response_acceptance': False}


def capture(transport, output, diagnose=False):
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
    if diagnose:
        record['schema_version'] = 3
        record['status'] = 'read-only-hosting-effective-header-diagnosis'
        record['effective_header_diagnosis'] = effective_diagnosis(version['config'])
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError('Fresh summary destination required')
    output.write_text(json.dumps(record, indent=2, ensure_ascii=False, allow_nan=False)+'\n', encoding='utf-8')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--diagnose-effective-headers', action='store_true')
    args = parser.parse_args()
    result = capture(Transport(os.environ.get('FIREBASE_HOSTING_ACCESS_TOKEN')), args.output,
                     diagnose=args.diagnose_effective_headers)
    print('Read-only allowlisted Hosting summary retained; activation remains unapproved')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Read-only Hosting summary failed; raw response omitted', file=sys.stderr)
        raise SystemExit(1) from None
