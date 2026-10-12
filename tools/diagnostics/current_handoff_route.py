"""Fixed current9ecd Linux phase observation, separate from release qualification."""
import argparse
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import time

from retained_handoff_route import sha, unpack, validate_metadata, run

SOURCE = '9ecd88481f0f4c3faf06662b992efab6c99a3849'
TREE = 'bde56805be17e12a80ab022b3b4c4513f67a49a2'
RUN = 38261547010
ARTIFACTS = {
    'web': (11753405515, 'little-leaf-web-'+SOURCE+'-1', '7afcafa8d6cc1241a7dfd23a8e650ee1e5cd300a1afc94d47f9810d3836c6cb9'),
    'evidence': (11753372705, 'little-leaf-firebase-evidence-'+SOURCE+'-1', '8e8be4e12b97960845c3140c20b5fdd83fca55d75cd514a4a5d026028a55672b'),
}
DRIVER = 'cbe37a713d59c20d9f1d5add35d9d5240f04e003ee838c93d1f6648203812da9'
OBSERVER = '7a05118efd4a10935eadf0792361e2f0bf5783ef0c6c0864967316a5a6cdcd07'
EXPORT = 'fe6102a697698f3f4df99009fbe83f276cd84c819726b7e6340aabbcf3bc0ca7'
NATIVE = '2dda0099ac971bfb174022cb5588e30c818bf7d520f8cd12a5507eeb25cfec5f'
REPORT = '6563f89be153a1fd372645c25f1744b4c7e729f16e3ad9f600dc29c275eeddb9'
ENTRY = 'f994f42e4e11082a8388a9b4630b9a8e28fb8756c7fbd68fa68ba3e7b70cc177'
PREFIX = 'web-build/evidence/firebase-fullflow/'
FLOW_SOURCES = (
    'firebase/fullflow.test.mjs', 'firebase/fullflow_fixtures.mjs', 'firebase/fullflow_network.mjs',
    'tests/diagnostics/probe_cloud_recovery_geometry.gd', 'tools/qualification/prepare_browser_qa.py',
    'web/little_leaf_firebase.js', 'web/little_leaf_firebase_session.js',
    'web/little_leaf_firebase_boot.mjs', 'web/little_leaf_update.js', 'firebase/firestore.rules',
)


def remaining():
    value = float(os.environ['LL_RETAINED_START_MONOTONIC'])+420-time.monotonic()
    if value <= 0:
        raise TimeoutError('Original current diagnostic work budget exhausted')
    return value


def source_hashes(source):
    return {name: sha(source/('platform/'+name if name.startswith(('firebase/', 'web/')) else name))
            for name in FLOW_SOURCES}


def validate_report(report, hashes):
    if (report.get('source_commit') != SOURCE or report.get('source_tree') != TREE
            or report.get('export_manifest_sha256') != EXPORT or report.get('native_report_sha256') != NATIVE
            or report.get('itch_entry_sha256') != ENTRY or report.get('headless_browser') is not False
            or report.get('passed') is not False or report.get('source_sha256') != hashes):
        raise ValueError('Original headed Linux source and failed evidence required')


def retained_report(root, source):
    path = root/'evidence'/PREFIX/'firebase-fullflow.json'
    if sha(path) != REPORT:
        raise ValueError('Exact failed current report required')
    report = json.loads(path.read_bytes())
    validate_report(report, source_hashes(source))
    return report


def validate_variant(root, report):
    folder = root/'variant'
    manifest = json.loads((folder/'firebase-variant-manifest.json').read_bytes())
    actual = {p.relative_to(folder).as_posix(): p for p in folder.rglob('*') if p.is_file()}
    files = manifest.get('files', {})
    if (not files or set(actual) != set(files) | {'firebase-variant-manifest.json'}
            or any(p.is_symlink() for p in folder.rglob('*'))):
        raise ValueError('Complete reconstructed diagnostic inventory required')
    for name, expected in files.items():
        path = PurePosixPath(name)
        if (path.is_absolute() or '..' in path.parts or chr(92) in name or ':' in name
                or sha(actual[name]) != expected):
            raise ValueError('Reconstructed diagnostic payload differs')
    inner = folder/'public/itch'
    if sha(inner/'index.html') != ENTRY:
        raise ValueError('Original Linux entry bytes not reproduced; preserve and STOP')
    for name in ['little_leaf_firebase.js', 'little_leaf_firebase_session.js',
                 'little_leaf_firebase_boot.mjs', 'little_leaf_update.js']:
        if sha(inner/name) != report['source_sha256']['web/'+name]:
            raise ValueError('Original current production module differs')
    base = json.loads((root/'build/web/release-manifest.json').read_bytes())
    for name in ['index.js', 'index.wasm', 'index.pck']:
        if sha(inner/name) != base['files'][name]['sha256']:
            raise ValueError('Retained compiled runtime differs')
    marker = json.loads((inner/'hosting-release.json').read_bytes())
    if (marker.get('source_commit') != SOURCE or marker.get('source_tree') != TREE
            or marker.get('ci_run_id') != str(RUN) or marker.get('runtime_path') != '/itch/'
            or marker.get('base_web_manifest_sha256') != EXPORT):
        raise ValueError('Original embedded source/manifest binding required')
    return sha(folder/'firebase-variant-manifest.json')


def overlay_hashes(source):
    folder = source/'platform/firebase'
    expected = {'current_handoff_driver.mjs': DRIVER, 'current_handoff_observer.mjs': OBSERVER}
    for name, digest in expected.items():
        if (folder/name).is_symlink() or sha(folder/name) != digest:
            raise ValueError('Exact separately reviewed observation overlay required')
    return expected


def prepare(root, coordinator):
    remaining()
    source = root/'source'
    original_run = json.loads((root/'run.metadata.json').read_bytes())
    for kind in ARTIFACTS:
        validate_metadata(kind, json.loads((root/(kind+'.metadata.json')).read_bytes()), original_run,
                          artifacts=ARTIFACTS, source=SOURCE, run_id=RUN)
    def git(value):
        return subprocess.check_output(['git', '-C', str(source), 'rev-parse', value],
                                       timeout=min(15, remaining())).decode().strip()
    if git('HEAD') != SOURCE or git('HEAD^{tree}') != TREE:
        raise ValueError('Exact current compiled source checkout required')
    frozen = coordinator/'platform/firebase/diagnostics'
    for name, digest in [('current_handoff_driver.mjs', DRIVER), ('current_handoff_observer.mjs', OBSERVER)]:
        if (frozen/name).is_symlink() or sha(frozen/name) != digest:
            raise ValueError('Frozen current observer bytes required')
    unpack(root/'web.zip', root/'build/web', ARTIFACTS['web'][2])
    selected = ['engine-evidence/summary.json', 'engine-evidence/test_cloud_recovery_ui.log',
                'engine-evidence/test_update_notice.log', PREFIX+'geometry-1-input.json',
                PREFIX+'geometry-1-result.json', PREFIX+'firebase-fullflow.json']
    unpack(root/'evidence.zip', root/'evidence', ARTIFACTS['evidence'][2], selected)
    native = root/'evidence/engine-evidence/summary.json'
    base = json.loads((root/'build/web/release-manifest.json').read_bytes())
    engine = json.loads(native.read_bytes())
    if (sha(root/'build/web/release-manifest.json') != EXPORT or sha(native) != NATIVE
            or base.get('source_commit') != SOURCE or base.get('source_tree') != TREE
            or engine.get('source_commit') != SOURCE or engine.get('status') != 'passed'
            or engine.get('player_save_used') is not False or base.get('test_report_sha256') != NATIVE):
        raise ValueError('Exact current native/export identity required')
    actual = {p.relative_to(root/'build/web').as_posix(): p for p in (root/'build/web').rglob('*') if p.is_file()}
    if set(actual) != set(base['files']) | {'release-manifest.json'}:
        raise ValueError('Exact retained Web member set required')
    for name, item in base['files'].items():
        path = PurePosixPath(name)
        if (path.is_absolute() or '..' in path.parts or chr(92) in name or ':' in name
                or sha(actual[name]) != item['sha256'] or actual[name].stat().st_size != item['bytes']):
            raise ValueError('Retained Web bytes differ')
    report = retained_report(root, source)
    remaining()
    sys.path.insert(0, str(source/'tools'))
    transformer = source/'tools/build/build_itch_trusted_preview.py'
    spec = importlib.util.spec_from_file_location('current_original_transform', transformer)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.prepare_stable(root/'build', root/'variant',
                          json.loads((source/'platform/firebase/public-config.json').read_bytes()), SOURCE, TREE)
    variant_sha = validate_variant(root, report)
    for name in ['current_handoff_driver.mjs', 'current_handoff_observer.mjs']:
        destination = source/'platform/firebase'/name
        if destination.exists():
            raise ValueError('New observation file must not replace retained source')
        shutil.copyfile(frozen/name, destination)
    overlay_hashes(source)
    retained_report(root, source)  # Original fullflow and all ten source hashes remain unchanged.
    receipt = {'diagnostic_only': True, 'deployable': False, 'release_qualification': False,
               'compiled_source': SOURCE, 'compiled_tree': TREE, 'original_failed_run': RUN,
               'driver_sha256': DRIVER, 'observer_sha256': OBSERVER, 'source_sha256': source_hashes(source),
               'export_manifest_sha256': EXPORT, 'native_sha256': NATIVE, 'original_failed_report_sha256': REPORT,
               'original_linux_entry_sha256': ENTRY, 'reconstructed_variant_manifest_sha256': variant_sha,
               'geometry_input_sha256': sha(root/'evidence'/PREFIX/'geometry-1-input.json'),
               'geometry_result_sha256': sha(root/'evidence'/PREFIX/'geometry-1-result.json'),
               'variant_is_reconstructed_not_retained_qualification': True, 'headless_browser': False,
               'first_cases': ['cache', 'graceful'], 'original_transfer_deadline_ms': 45000,
               'new_engine_or_geometry': False, 'original_fullflow_file_unchanged': True}
    with (root/'diagnostic-binding.json').open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(receipt, indent=2)+'\n'); stream.flush(); os.fsync(stream.fileno())
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream:
            stream.write('LL_CURRENT_BINDING_SHA256='+sha(root/'diagnostic-binding.json')+'\n')
    remaining()
    return receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--coordinator', type=Path, required=True)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve()
    if args.run:
        remaining()
        if sha(root/'diagnostic-binding.json') != os.environ.get('LL_CURRENT_BINDING_SHA256'):
            raise ValueError('Original preparation receipt must remain unchanged')
        binding = json.loads((root/'diagnostic-binding.json').read_bytes())
        report = retained_report(root, root/'source')
        if (validate_variant(root, report) != binding['reconstructed_variant_manifest_sha256']
                or source_hashes(root/'source') != binding['source_sha256']
                or sha(root/'evidence'/PREFIX/'geometry-1-input.json') != binding['geometry_input_sha256']
                or sha(root/'evidence'/PREFIX/'geometry-1-result.json') != binding['geometry_result_sha256']):
            raise ValueError('Prepared current diagnostic inputs changed')
        overlay_hashes(root/'source')
        run(root, os.environ, driver='current_handoff_driver.mjs')
    else:
        prepare(root, args.coordinator.resolve())


if __name__ == '__main__':
    main()
