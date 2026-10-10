"""Reuse the original publication's pinned main CI artifact, never a later run."""
import argparse
import json
import os
from pathlib import Path

from firebase_release_event import artifact_for
from firebase_release_gate import QUALIFICATION_WORKFLOW, require, trusted_run
import reuse_main_ci as reuse
from stage_released_firebase import IDENTITY, source_identity


def prepare(api, root, selection, output):
    source_identity(root, selection)
    expected = selection['qualification']
    run = api.read(f"actions/runs/{expected['qualification_run_id']}")
    trusted_run(run, QUALIFICATION_WORKFLOW, ('push', 'workflow_dispatch'))
    require(run['head_branch'] == 'main' and run['head_sha'] == selection['source_commit']
            and run['run_attempt'] == expected['qualification_attempt'], 'Original main run/attempt changed')
    reuse.require_jobs(api.pages(f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs", 'jobs'))
    artifact = artifact_for(api, run, f"little-leaf-web-{run['head_sha']}-{run['run_attempt']}")
    require(artifact['id'] == expected['artifact_id'] and artifact['digest'] == expected['artifact_digest'],
            'The original publication artifact is missing or changed')
    output.mkdir(parents=True, exist_ok=False)
    reuse.extract(api.read(f"actions/artifacts/{artifact['id']}/zip", binary=True),
                  artifact['digest'].removeprefix('sha256:'), output / 'web')
    manifest = reuse.bind_package(output / 'web', root, selection['source_commit'], selection['source_tree'], run)
    original_hash = reuse.sha256(output / 'web/release-manifest.json')
    require(original_hash == expected['qualified_manifest_sha256'], 'Original release manifest changed')
    reuse.packed_smoke(output / 'web', output)
    receipt = {**expected, 'tag': '', 'qualified_payload_unchanged': True, 'packed_startup': 'passed'}
    require(all(receipt[k] == expected[k] for k in IDENTITY), 'Original qualification identity changed')
    manifest['release_reuse'] = receipt
    (output / 'web/release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    reuse.validate_export_inventory(output / 'web')
    (output / 'qualification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['source-root', 'selection', 'output']:
        p.add_argument('--' + name, type=Path, required=True)
    args = p.parse_args()
    print(json.dumps(prepare(reuse.GitHub(os.environ.get('GH_TOKEN', '')), args.source_root.resolve(),
                            json.loads(args.selection.read_text()), args.output.resolve())))


if __name__ == '__main__':
    main()
