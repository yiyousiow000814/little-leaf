"""Prepare the explicit own-origin iframe variant; never deploy or authorize domains."""
import json
import re
import shutil
from pathlib import Path
from build_firebase import stage, validate_export_inventory, entry_styles
from build_web import ROOT, sha256
from project_layout import source_path


def wrapper_html(html, origin):
    if not re.fullmatch(r'https://little-leaf-41e5d--itch-embed-test-[a-z0-9]+\.web\.app', origin):
        raise ValueError('Exact controlled preview origin required')
    entry = '<section id="itch-entry" class="leaf-entry-page" aria-labelledby="entry-heading"><div class="leaf-entry-card"><p class="leaf-entry-brand">Little Leaf</p><p class="leaf-entry-eyebrow">A little café of your own</p><h1 id="entry-heading" class="leaf-entry-title">Welcome to your café</h1><p class="leaf-entry-intro">Choose how you\'d like to begin.</p><div class="leaf-entry-actions"><div class="leaf-entry-option"><button id="itch-account" type="button">Play with Google on itch</button><p>Sign in through a secure Google popup on this itch page.</p></div><div class="leaf-entry-option local"><button id="itch-local" type="button">Continue local play on itch</button><p>Return to your café saved in this browser.</p></div></div><p class="leaf-entry-note">Local progress does not transfer automatically to your Google account.</p></div></section>'
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
            const back=document.createElement('button');back.textContent='Back to play choices';
            back.className='leaf-entry-back';
            back.addEventListener('click',()=>root.location.reload());document.body.append(frame,back);
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
    marker_path.write_text(json.dumps(marker, indent=2)+'\n')
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
        'assets/fonts/Nunito-OFL.txt', 'tools/build_firebase.py', 'tools/build_itch_trusted_preview.py']}
    manifest['files'] = {p.relative_to(output).as_posix():sha256(p) for p in sorted(output.rglob('*'))
                         if p.is_file() and p != manifest_path}
    manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
    return manifest
