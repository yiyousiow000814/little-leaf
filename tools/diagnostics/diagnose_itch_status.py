"""Fixed-target read-only Butler diagnosis. Never emit command output or publish."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ci.install_tools import LOCK
from publish_itch import TARGET, parse_result, channel


def classify(code, output):
    """Return literals only; untrusted output never becomes a report field."""
    statuses = set(re.findall(r'(?:HTTP(?:/[0-9.]+)?\s+|status(?: code)?[\s:=]+)(401|403|404|429|5[0-9]{2})\b', output, re.I))
    status = int(next(iter(statuses))) if len(statuses) == 1 else None
    if status is not None:
        return 'http-' + ('5xx' if status >= 500 else str(status)), status
    for category, expression in [
        ('dns', r'no such host|temporary failure in name resolution|could not resolve'),
        ('tls', r'TLS handshake|x509:|certificate verify|certificate signed by unknown'),
        ('deadline', r'context deadline exceeded|i/o timeout|request canceled.*timeout'),
        ('connection', r'connection refused|connection reset|network is unreachable'),
        ('authentication', r'invalid api key|invalid credentials|authentication failed'),
    ]:
        if re.search(expression, output, re.I):
            return category, None
    return ('ok' if code == 0 else 'command-failed-unclassified'), None


def command(binary, arguments, *, authenticated=False):
    environment = os.environ.copy()
    # Go HTTP debug can print Authorization. Never inherit or enable it.
    for name in ('GO_ITCHIO_DEBUG', 'BUTLER_HTTP_DEBUG', 'BUTLER_DEBUG_PORT', 'BUTLER_DEBUG_HOST'):
        environment.pop(name, None)
    if not authenticated:
        environment.pop('BUTLER_API_KEY', None)
    try:
        result = subprocess.run([str(binary), *arguments], env=environment,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, errors='replace', timeout=60)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return None, '', 'context deadline exceeded'
    except OSError:
        return None, '', ''


def preflight(binary):
    version_code, version_stdout, version_stderr = command(binary, ['--version'])
    # Kingpin writes --version to stderr; retain neither stream in the report.
    version_text = version_stdout + '\n' + version_stderr
    expected = LOCK['butler']['version']
    matched = version_code == 0 and bool(re.search(r'(?<![0-9.])v?' + re.escape(expected) + r'(?![0-9.])', version_text))
    help_code, _, _ = command(binary, ['status', '--help'])
    return {'phase': 'credential-free-preflight', 'installed_version': expected if matched else None,
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'archive_sha256': LOCK['butler']['sha256'], 'version_exit_code': version_code,
        'help_exit_code': help_code, 'passed': matched and help_code == 0,
        'publication_allowed': False}


def status(binary, previous):
    if (set(previous) != {'phase', 'passed', 'installed_version', 'archive_sha256',
            'binary_sha256', 'version_exit_code', 'help_exit_code', 'publication_allowed'}
            or type(previous.get('version_exit_code')) is not int or previous['version_exit_code'] != 0
            or type(previous.get('help_exit_code')) is not int or previous['help_exit_code'] != 0
            or previous.get('publication_allowed') is not False
            or previous.get('phase') != 'credential-free-preflight' or previous.get('passed') is not True
            or previous.get('installed_version') != LOCK['butler']['version']
            or previous.get('binary_sha256') != hashlib.sha256(binary.read_bytes()).hexdigest()
            or previous.get('archive_sha256') != LOCK['butler']['sha256']):
        raise ValueError('Pinned credential-free preflight required')
    if not os.environ.get('BUTLER_API_KEY'):
        return {'phase': 'status-only', 'exit_code': None, 'category': 'missing-credential',
            'http_status': None, 'channel_identity_verified': False, 'publication_allowed': False}
    code, stdout, stderr = command(binary, ['--json', 'status', TARGET], authenticated=True)
    category, http_status = classify(code, stdout + '\n' + stderr)
    identity = False
    head_state, head_build_id, pending = None, None, None
    if code == 0:
        try:
            current = channel(parse_result(stdout))
            identity = True
            category, http_status = 'ok', None
            head = current.get('head') or {}
            head_state = head.get('state') if head.get('state') in ('completed', 'processing', 'failed') else 'unknown'
            build_id = head.get('id')
            head_build_id = build_id if type(build_id) is int and build_id > 0 else None
            pending = bool(current.get('pending'))
        except (ValueError, KeyError, TypeError):
            category = 'response-schema'
    return {'phase': 'status-only', 'exit_code': code, 'category': category,
        'http_status': http_status, 'channel_identity_verified': identity,
        'channel_head_state': head_state, 'channel_head_build_id': head_build_id, 'channel_pending': pending,
        'publication_allowed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--phase', choices=['preflight', 'status'], required=True)
    parser.add_argument('--preflight', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.phase == 'preflight':
            report = preflight(args.binary)
        else:
            report = status(args.binary, json.loads(args.preflight.read_text()))
    except Exception:
        # Exception bodies can contain subprocess arguments, URLs or credentials.
        report = {'phase': args.phase, 'category': 'diagnostic-internal-error', 'publication_allowed': False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    if args.phase == 'preflight' and not report.get('passed'):
        raise SystemExit(1)
    if report.get('category') == 'diagnostic-internal-error':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
