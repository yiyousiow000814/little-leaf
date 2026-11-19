"""Produce only fixed synthetic diagnostic fields; never publish report, logs or profiles."""
from datetime import datetime
import json
from pathlib import Path
import sys

EVENTS = {'visibilitychange', 'pagehide', 'pageshow', 'focus', 'blur', 'authority_put',
          'authority_durable', 'authority_aborted', 'controller_calls_vault', 'vault_acknowledgement'}
LOG_EVENTS = {'save_requested', 'save_queued', 'save_skipped', 'save_validated', 'save_submitted',
              'save_confirmed', 'save_accepted', 'save_failure', 'connection_closed', 'connection_reopen_requested'}
VIS = {'hidden', 'visible', 'prerender'}
HEIGHTS = {'full', 'half'}
LAYERS = {'controller', 'native', 'vault'}
FORMATS = {'little_leaf.grid_building.v2', 'little_leaf.grid_building.v1'}
CODES = {'REVISION_CONFLICT', 'SAVE_BUSY', 'REVISION_LIMIT', 'INVALID_REVISION_ACK', 'WRITES_SUPPRESSED',
         'INVALID_ACK', 'RECOVERY_BLOCKED', 'STORAGE_ERROR', 'STORAGE_ABORT', 'STORAGE_BLOCKED'}

def integer_fields(src, dst, keys):
    for k in keys:
        v = src.get(k)
        if type(v) is int and 0 <= v <= 1000000:
            dst[k] = v

def categories(src, dst, mapping):
    for k, allowed in mapping.items():
        v = src.get(k)
        if isinstance(v, str) and v in allowed:
            dst[k] = v

def bools(src, dst, keys):
    for k in keys:
        if type(src.get(k)) is bool:
            dst[k] = src[k]

def relative(entry, key, delta, dst):
    val = entry.get(key)
    if type(val) in (int, float) and -900000 <= val - delta <= 900000:
        dst['ms_since_apply'] = round(val - delta, 3)

def timeline(arm, start):
    if not isinstance(arm, dict):
        return {'available': False}
    out = {'available': True, 'timeline': [], 'controller': [], 'save_acknowledgements': []}
    integer_fields(arm, out, ['dropped', 'save_starts'])
    lists = [('timeline', 'timeline', 96), ('controller_log', 'controller', 240), ('acks', 'save_acknowledgements', 96)]
    for src, dst, cap in lists:
        events = arm.get(src, [])
        if not isinstance(events, list):
            continue
        if len(events) > cap:
            out[src+'_omitted'] = len(events)-cap
        for e in events[-cap:]:
            if not isinstance(e, dict):
                continue
            r = {}
            if src == 'timeline':
                categories(e, r, {'event': EVENTS, 'visible': VIS, 'wall_height': HEIGHTS, 'building_format': FORMATS, 'code': CODES})
                if 'event' not in r:
                    continue
                relative(e, 'epoch_ms', start, r)
                integer_fields(e, r, ('revision', 'expected_revision', 'format', 'coins', 'served', 'wall_cost'))
                bools(e, r, ('focused', 'persisted', 'durable', 'ok', 'open'))
            elif src == 'controller_log':
                categories(e, r, {'event': LOG_EVENTS, 'layer': LAYERS, 'code': CODES})
                if 'event' not in r:
                    continue
                if isinstance(e.get('timestamp'), str):
                    try:
                        val = datetime.fromisoformat(e['timestamp'])
                        if val.tzinfo is not None:
                            relative({'t': val.timestamp()*1000}, 't', start, r)
                    except (ValueError, OverflowError, OSError):
                        pass
                integer_fields(e, r, ('revision', 'sequence'))
            else:
                categories(e, r, {'code': CODES})
                integer_fields(e, r, ('revision', 'creditedCoins'))
                bools(e, r, ('durable', 'ok'))
            if r:
                out[dst].append(r)
    return out

def summarize(path):
    out = {'schema': 'll-case-b-observer-summary-v1', 'producer_run': 44490633657, 'producer_attempt': 1,
           'current': '8f38cd8b46345603d41f4fe2199904e26dad4a52', 'historical': '9110ebd9a2d6cbf4d2af303be0e244e660c0f7fc',
           'case': 'already_open_old', 'status': 'case_not_observed'}
    if not path.is_file():
        return out
    report = json.loads(path.read_text())
    if report.get('synthetic_only') is not True or set(report.get('cases', {})) - {'already_open_old'}:
        raise ValueError('unexpected non-synthetic case scope')
    if report.get('status') == 'passed' and report.get('browser_verified') is True:
        out['status'] = 'passed_without_reproduction'
        return out
    e = report.get('apply_revision_failure')
    if not isinstance(e, dict) or e.get('synthetic_only') is not True:
        out['status'] = 'different_case_failure'
        return out
    b = report.get('new_ui_edit', {})
    if not isinstance(b, dict) or type(b.get('revision_before')) is not int or type(b.get('revision_after')) is not int or e.get('expected_revision') != b['revision_before'] + 1 or e.get('observed_revision') != b['revision_after'] or e['expected_revision'] == e['observed_revision']:
        raise ValueError('inconsistent failure receipt')
    out['status'] = 'strict_revision_failure_observed'
    integer_fields(b, out, ['revision_before', 'revision_after'])
    integer_fields(e, out, ['expected_revision', 'observed_revision'])
    out['confirm_probe'] = {}
    integer_fields(e.get('confirm_probe', {}), out['confirm_probe'], ['save_starts', 'acknowledgements'])
    start = e.get('apply_started_epoch_ms')
    if type(start) not in (int, float) or not 0 < start < 1e15:
        raise ValueError('missing relative time anchor')
    out['old'] = timeline(e.get('old'), start)
    out['new'] = timeline(e.get('new'), start)
    return out

if __name__ == '__main__':
    src, out = map(Path, sys.argv[1:3])
    report = summarize(src/'wall-compatibility-browser.json')
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2)+'\n')
