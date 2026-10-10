"""Read-only release selection for automatic Firebase staging; never deploy.

Only a completed Butler publication and its immutable qualification receipt may
select a source. Workflow event fields are wake-ups, never trusted inputs.
"""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile

from firebase_release_gate import REPOSITORY, plan_release, require, trusted_run, ITCH_WORKFLOW
from reuse_main_ci import GitHub, require_jobs
from release_metadata import version


def extract_tree(data, digest, destination):
    require(digest == 'sha256:' + hashlib.sha256(data).hexdigest(), 'Artifact ZIP digest mismatch')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        members = archive.infolist()
        require(len(members) <= 5000 and sum(m.file_size for m in members) <= 200 * 1024 * 1024,
                'Artifact extraction exceeds bounds')
        seen = set()
        for member in members:
            name = member.filename
            path = PurePosixPath(name)
            require(name and name == member.orig_filename
                    and not path.is_absolute() and all(p not in {'.', '..'} for p in path.parts)
                    and path.as_posix() == name.rstrip('/')
                    and not any(c in name for c in '\\:\r\n')
                    and not any(p.startswith('.') for p in path.parts)
                    and not stat.S_ISLNK(member.external_attr >> 16)
                    and name.casefold() not in seen, 'Unsafe or duplicate artifact path')
            seen.add(name.casefold())
        destination.mkdir(parents=True, exist_ok=False)
        for member in members:
            target = destination / member.filename
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(member))


def artifact_for(api, run, name):
    matches = [a for a in api.pages(f"actions/runs/{run['id']}/artifacts", 'artifacts') if a['name'] == name]
    require(len(matches) == 1, 'Missing or ambiguous artifact: ' + name)
    artifact = matches[0]
    require(artifact.get('expired') is False and artifact.get('workflow_run', {}).get('id') == run['id']
            and artifact['workflow_run'].get('head_sha') == run['head_sha']
            and re.fullmatch(r'sha256:[0-9a-f]{64}', artifact.get('digest', '')),
            'Untrusted artifact origin/digest')
    return artifact


def download(api, artifact, destination):
    extract_tree(api.read(f"actions/artifacts/{artifact['id']}/zip", binary=True), artifact['digest'], destination)


def peel(api, tag):
    obj = api.read('git/ref/tags/' + tag)['object']
    for _ in range(4):
        if obj['type'] == 'commit':
            return obj['sha']
        require(obj['type'] == 'tag', 'Invalid release tag object')
        obj = api.read('git/tags/' + obj['sha'])['object']
    raise ValueError('Tag chain exceeds bounds')


def select(api, run_id, output):
    run = api.read(f'actions/runs/{run_id}')
    trusted_run(run, ITCH_WORKFLOW)
    tag = run['head_branch']
    require(re.fullmatch(r'v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)[a-z]?', tag),
            'Only an immutable version release may stage')
    sha = peel(api, tag)
    commit = api.read('git/commits/' + sha)
    require(api.read(f'compare/{sha}...main').get('status') in {'ahead', 'identical'},
            'Released source must be in main history')
    metadata = output / 'tagged-metadata/game'
    (metadata / 'data').mkdir(parents=True)
    for name in ['project.godot', 'data/release_notes.json']:
        content = api.read(f'contents/game/{name}?ref={sha}')
        require(content.get('encoding') == 'base64', 'Immutable tagged metadata must be plain content')
        (metadata / name).write_bytes(base64.b64decode(content['content']))
    project_version = version(metadata.parent, tag)
    jobs = api.pages(f"actions/runs/{run_id}/attempts/{run['run_attempt']}/jobs", 'jobs')
    publication_artifact = artifact_for(api, run,
        f"little-leaf-itch-publication-{sha}-{run['run_attempt']}")
    download(api, publication_artifact, output / 'publication')
    publication = json.loads((output / 'publication/receipt.json').read_text())
    receipt = publication['qualification']
    require(publication.get('state') == 'completed' and type(publication.get('itch_build_id')) is int
            and publication['itch_build_id'] > 0 and publication.get('source_commit') == sha
            and publication.get('tag') == tag and publication.get('version') == tag[1:]
            and publication.get('target') == 'siowyiyou/little-leaf:html5'
            and str(publication.get('workflow_run')) == str(run_id)
            and str(publication.get('workflow_attempt')) == str(run['run_attempt'])
            and re.fullmatch(r'[0-9a-f]{64}', publication.get('release_manifest_sha256', '')),
            'A confirmed exact-attempt Butler receipt is required')
    qa = artifact_for(api, run, f"little-leaf-release-qualification-{sha}-{run['run_attempt']}")
    download(api, qa, output / 'release-qualification')
    require(json.loads((output / 'release-qualification/qualification.json').read_text()) == receipt,
            'Publication qualification differs from immutable receipt')
    require(receipt.get('tag') == tag and receipt.get('qualified_payload_unchanged') is True,
            'Released runtime must preserve qualified bytes')
    qualification_run = api.read(f"actions/runs/{receipt['qualification_run_id']}")
    require_jobs(api.pages(f"actions/runs/{qualification_run['id']}/attempts/{qualification_run['run_attempt']}/jobs", 'jobs'))
    artifact = api.read(f"actions/artifacts/{receipt['artifact_id']}")
    plan = plan_release(release_run=run, publish_jobs=jobs, tag=tag, tag_commit=sha,
        tag_tree=commit['tree']['sha'], project_version=project_version, qualification_run=qualification_run,
        qualification_receipt=receipt, qualification_artifact=artifact)
    require(artifact.get('name') == f"little-leaf-web-{sha}-{qualification_run['run_attempt']}"
            and artifact['workflow_run'].get('head_sha') == sha, 'Wrong ordinary artifact')
    plan.update(status='qualified-release-selected-staging-only', qualification=receipt,
        publication_artifact=publication_artifact, publication=publication,
        live_status='security-cutover-blocked', dispatch_allowed=False)
    (output / 'selection.json').write_text(json.dumps(plan, indent=2) + '\n')
    return plan


def reserve(api, release_run):
    require(os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'Inspect an uncertain prior attempt; no automatic retry')
    require(type(release_run) is int and release_run > 0, 'Positive release run required')
    name = f'little-leaf-firebase-request-{release_run}'
    # Server-side filtering keeps the bounded inventory independent of unrelated
    # repository artifacts. Expired matching intents still prohibit a retry.
    require(not any(a.get('name') == name for a in api.pages(f'actions/artifacts?name={name}', 'artifacts')),
            'Existing or expired staging intent; inspect it before retrying')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--release-run', type=int, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--reserve', action='store_true', help='Refuse any prior staging intent before emitting outputs')
    args = p.parse_args()
    require(args.release_run > 0, 'Positive release run required')
    api = GitHub(os.environ.get('GH_TOKEN', ''))
    if args.reserve:
        reserve(api, args.release_run)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    plan = select(api, args.release_run, output)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            for key, value in {'source_sha': plan['source_commit'], 'release_tag': plan['release_tag'],
                               'release_run_id': args.release_run}.items():
                stream.write(f'{key}={value}\n')
    print(json.dumps({k: plan[k] for k in ['status', 'source_commit', 'source_tree', 'release_tag', 'live_status']}))


if __name__ == '__main__':
    main()
