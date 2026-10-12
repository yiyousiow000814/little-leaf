"""Prepare the explicit own-origin iframe variant; never deploy or authorize domains."""
import json
import re
import shutil
from pathlib import Path
if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build.build_firebase import stage, validate_export_inventory, entry_styles, update_hosting_marker
from build.build_web import ROOT, sha256
from build.project_layout import source_path
from build.build_itch_entry import ENTRY, remove_ordinary_entry


STABLE_ORIGIN = 'https://little-leaf-41e5d.firebaseapp.com'
STABLE_PATH = '/itch/'


def wrapper_html(html, origin, *, stable=False):
    valid = origin == STABLE_ORIGIN + STABLE_PATH.rstrip('/') if stable else bool(re.fullmatch(r'https://little-leaf-41e5d--itch-embed-test-[a-z0-9]+\.web\.app', origin))
    if not valid:
        raise ValueError('Exact controlled preview origin required')
    html = remove_ordinary_entry(html)
    # Reuse the reviewed presentation while preserving the existing frame controller IDs.
    # Only this explicit preview replaces the outbound link; ordinary release stays unchanged.
    outbound = '<a id="itch-release-account" aria-describedby="itch-account-detail itch-progress-separation" class="leaf-entry-link" href="https://little-leaf-41e5d.firebaseapp.com/" target="_blank" rel="noopener noreferrer">Play with Google · opens a new tab</a>'
    if ENTRY.count(outbound) != 1:
        raise ValueError('Reviewed ordinary account entry contract changed')
    entry = ENTRY.replace(outbound, '<button id="itch-account" aria-describedby="itch-account-detail itch-progress-separation" type="button">Play with Google</button>')
    entry = entry.replace('id="itch-release-entry"', 'id="itch-entry"').replace('id="itch-release-local"', 'id="itch-local"')
    entry = entry.replace('>Continue local play on itch</button>', '>Continue local play</button>')
    entry = entry.replace('Open the official account game, then sign in with Google.', 'Sign in through a secure Google popup, then continue playing on this itch page.')
    # Gate only the derived wrapper before its original vault or engine starts.
    marker = 'window.__littleLeafVault.boot()'
    if html.count(marker) != 1:raise ValueError('Original local boot contract changed')
    html = html.replace(marker, 'window.LittleLeafItchEntryReady.then(() => window.__littleLeafVault.boot())')
    controller = '''/* Little Leaf trusted-preview wrapper. No account SDK, tokens, save payloads or messages. */
(function(root){
    'use strict';
    root.LittleLeafItchEntryReady=new Promise(resolve=>{
        const entry=document.getElementById('itch-entry'),local=document.getElementById('itch-local'),account=document.getElementById('itch-account');
        const canvas=document.getElementById('canvas'),status=document.getElementById('status');
        let selected=false;
        entry.hidden=false;canvas.hidden=true;status.hidden=true;
        local.addEventListener('click',()=>{
            if(selected)return;selected=true;
            entry.hidden=true;canvas.hidden=false;status.hidden=false;canvas.focus();resolve();
        });
        account.addEventListener('click',()=>{
            if(selected)return;selected=true;
            local.disabled=true;account.disabled=true;entry.hidden=true;
            const frame=document.createElement('iframe');frame.title='Little Leaf account game';
            frame.style.cssText='position:fixed;inset:0;width:100%;height:100%;border:0;background:#fffaf0;z-index:60';
            frame.setAttribute('allow','fullscreen; autoplay');frame.setAttribute('allowfullscreen','');
            frame.src=PREVIEW_ORIGIN+'/';
            // Returning to local play must be confirmed inside the trusted game
            // after its save/pending guards; the wrapper cannot safely decide.
            document.body.append(frame);
        });
    });
})(window);
'''.replace('PREVIEW_ORIGIN', json.dumps(origin))
    if '<body>' not in html:raise ValueError('Original body contract changed')
    engine = '<script src="index.js"></script>'
    if html.count(engine) != 1:raise ValueError('Original engine script contract changed')
    html = html.replace('<body>', '<body><style>'+entry_styles()+'</style>'+entry, 1)
    # Required canvas/status nodes have been parsed; gate exists before engine boot.
    return html.replace(engine, '<script>'+controller+'</script>'+engine, 1)


def prepare(build, output, config, origin, source, tree):
    if not re.fullmatch(r'[0-9a-f]{40}', source) or not re.fullmatch(r'[0-9a-f]{40}', tree):
        raise ValueError('Exact reviewed candidate source identity required')
    base = validate_export_inventory(build)
    inputs = base.get('production_sha256', {})
    if not inputs or base.get('packed_smoke') != 'passed' or base.get('engine_checks', 0) <= 0:
        raise ValueError('Reviewed complete engine/export provenance required')
    for name, digest in inputs.items():
        if name != 'web/little_leaf_firebase_boot.mjs' and sha256(source_path(ROOT, name)) != digest:
            raise ValueError('Reviewed engine or local-shell input changed: '+name)
    # Validates the exact origin and complete base before writing an output directory.
    stage(build, output, config, trusted_itch_origin=origin)
    # The old outbound launcher is not the uploaded test wrapper.
    (output / 'itch-entry/index.html').unlink()
    (output / 'itch-entry').rmdir()
    marker_path = output / 'public/hosting-release.json'
    marker = json.loads(marker_path.read_text())
    marker.update(source_commit=source, source_tree=tree,
                  engine_source_commit=base['source_commit'], engine_source_tree=base['source_tree'],
                  test_surface='trusted-itch-frame', runtime_origin=origin)
    update_hosting_marker(output/'public',marker)
    wrapper = output / 'itch-wrapper'
    shutil.copytree(build / 'web', wrapper)
    (wrapper / 'release-manifest.json').unlink()
    (wrapper / 'index.html').write_text(wrapper_html((wrapper / 'index.html').read_text(encoding='utf-8'), origin),encoding='utf-8')
    manifest_path = output / 'firebase-variant-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest.update(source_commit=source, source_tree=tree, runtime_origin=origin,
                    status='prepared-local-test-artifact-not-deployed', hosted_acceptance=False,
                    auth_domains_modified=False, production_release_eligible=False,
                    ancestor_origins=['https://html-classic.itch.zone', 'https://siowyiyou.itch.io'],
                    engine_reuse={'source_commit':base['source_commit'], 'source_tree':base['source_tree'],
                                  'new_engine_run':False, 'gameplay_godot_inputs_byte_identical':True,
                                  'compared_production_inputs':len(inputs)-1,
                                  'base_test_report_sha256':base.get('test_report_sha256'),
                                  'native_checks':base.get('engine_checks'), 'native_processes':base.get('test_processes')})
    manifest['source_sha256'] = {name:sha256(source_path(ROOT, name)) for name in [
        'web/little_leaf_firebase_boot.mjs', 'web/little_leaf_firebase.js',
        'web/little_leaf_firebase_session.js', 'web/little_leaf_update.js',
        'web/little_leaf_shell.html', 'web/little_leaf_entry.css', 'assets/fonts/Nunito-Variable.ttf',
        'assets/fonts/Nunito-OFL.txt', 'tools/build/build_firebase.py', 'tools/build/build_itch_entry.py',
        'tools/build/build_itch_trusted_preview.py']}
    manifest['files'] = {p.relative_to(output).as_posix():sha256(p) for p in sorted(output.rglob('*'))
                         if p.is_file() and p != manifest_path}
    manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
    return manifest


def prepare_stable(build, output, config, source, tree, publication=None):
    """Prepare a nondeployable stable-path candidate from exact-source runtime bytes.

    This does not enable the live selector or mutate Hosting/Auth configuration.
    Its proposed headers and complete inventories are review artifacts only.
    """
    base = validate_export_inventory(build)
    if (not re.fullmatch(r'[0-9a-f]{40}', source)
            or not re.fullmatch(r'[0-9a-f]{40}', tree)
            or base.get('source_commit') != source or base.get('source_tree') != tree
            or base.get('packed_smoke') != 'passed' or base.get('engine_checks', 0) <= 0
            or not base.get('production_sha256')):
        raise ValueError('Exact-source reviewed engine/export provenance required')
    for name, expected in base['production_sha256'].items():
        if sha256(source_path(ROOT, name)) != expected:
            raise ValueError('Same-itch source input changed: ' + name)
    if config.get('projectId') != 'little-leaf-41e5d' or config.get('authDomain') != 'little-leaf-41e5d.firebaseapp.com':
        raise ValueError('Existing official Firebase origin required')
    stage(build, output, config, publication=publication)
    public = output / 'public'
    original = sorted(public.iterdir())
    if any(not path.is_file() or path.is_symlink() for path in original):
        raise ValueError('Flat verified base inventory required')
    embedded = public / 'itch'
    embedded.mkdir()
    for path in original:
        shutil.copy2(path, embedded / path.name)
    html_path = embedded / 'index.html'
    html = html_path.read_text(encoding='utf-8')
    call = 'm.start(' + json.dumps(config).replace('<', '\\u003c') + ')'
    options = {'surface':'trusted-itch-frame', 'runtimeOrigin':STABLE_ORIGIN, 'runtimePath':STABLE_PATH}
    if html.count(call) != 1:
        raise ValueError('Exact top-level bootstrap required')
    html_path.write_text(html.replace(call, call[:-1] + ',' + json.dumps(options) + ')'), encoding='utf-8')
    marker = json.loads((embedded / 'hosting-release.json').read_text())
    marker.update(runtime_origin=STABLE_ORIGIN, runtime_path=STABLE_PATH, test_surface='trusted-itch-frame')
    update_hosting_marker(embedded, marker)
    wrapper = output / 'itch-wrapper'
    shutil.copytree(build / 'web', wrapper)
    (wrapper / 'release-manifest.json').unlink()
    (wrapper / 'index.html').write_text(wrapper_html((wrapper / 'index.html').read_text(encoding='utf-8'),
                                                  STABLE_ORIGIN + STABLE_PATH.rstrip('/'), stable=True), encoding='utf-8')
    hosting = json.loads((output / 'firebase.json').read_text())['hosting']
    policy = 'frame-ancestors https://html-classic.itch.zone https://siowyiyou.itch.io'
    # The existing HTML suffix rule already supplies index.html's no-cache.
    # Preserve it; do not depend on duplicate-header resolution by the provider.
    additions = [
        {'source':'/itch/', 'headers':[
            {'key':'Content-Security-Policy', 'value':policy}, {'key':'Cache-Control', 'value':'no-cache'}]},
        {'source':'/itch/index.html', 'headers':[{'key':'Content-Security-Policy', 'value':policy}]},
        {'source':'/itch/hosting-release.json', 'headers':[{'key':'Cache-Control', 'value':'no-store'}]},
    ]
    hosting['headers'].extend(additions)
    (output / 'firebase.json').write_text(json.dumps({'hosting':hosting}, indent=2)+'\n')
    manifest_path = output / 'firebase-variant-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest.update(status='prepared-same-itch-local-candidate-not-deployable', source_commit=source, source_tree=tree,
                    runtime_origin=STABLE_ORIGIN, runtime_path=STABLE_PATH, hosted_acceptance=False,
                    production_release_eligible=False, auth_domains_modified=False,
                    hosting_header_additions=additions, hosting_config_proposal_only=True,
                    source_sha256={name:sha256(source_path(ROOT, name)) for name in [
                        'tools/build/build_itch_entry.py','tools/build/build_itch_trusted_preview.py','tools/build/build_firebase.py',
                        'web/little_leaf_firebase_boot.mjs','web/little_leaf_firebase_session.js','web/little_leaf_update.js',
                        'web/little_leaf_entry.css']})
    manifest['files'] = {path.relative_to(output).as_posix():sha256(path) for path in sorted(output.rglob('*'))
                         if path.is_file() and path != manifest_path}
    manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
    return manifest
