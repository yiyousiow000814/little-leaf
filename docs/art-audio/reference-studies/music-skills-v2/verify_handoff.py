#!/usr/bin/env python3
"""Check the exact four handoff files without running source or contacting services."""
import argparse, hashlib, json, zipfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--directory', type=Path, required=True)
a=p.parse_args()
root=Path(__file__).resolve().parent
reg=json.loads((root/'repo_patch/docs/art-audio/reference-studies/music-reference-register.json').read_text())
for item in reg['references']:
    if item['id'] in {'full-corner-cafe-v2','daybreak-steps-104-and-112'}:continue
    if 'container' in item:
        path=a.directory/item['container']
        if not path.is_file():raise SystemExit(f'Missing: {path.name}')
        if 'container_sha256' in item and hashlib.sha256(path.read_bytes()).hexdigest()!=item['container_sha256']:
            raise SystemExit(f'Wrong archive: {path.name}')
        with zipfile.ZipFile(path) as z:data=z.read(item['member'])
    else:
        path=a.directory/item['file']
        if not path.is_file():raise SystemExit(f'Missing: {path.name}')
        data=path.read_bytes()
    if hashlib.sha256(data).hexdigest()!=item['sha256']:raise SystemExit(f'Wrong recording: {item["id"]}')
    print('MATCH',item['id'],item['status'])
print('Identity checks passed. No creative, gameplay or release approval implied.')
