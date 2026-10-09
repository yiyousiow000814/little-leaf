"""Compare fixed-position PNGs (exact encoded bytes); retain receipts even on failure."""
import hashlib
import json
from pathlib import Path
import sys
baseline, candidate = map(Path, sys.argv[1:])
left = json.loads((baseline/'captures.json').read_text())['records']
right = json.loads((candidate/'captures.json').read_text())['records']
assert left == right and len(left) == 10
comparisons = []
for record in left:
    filename = record['file']
    a = hashlib.sha256((baseline/filename).read_bytes()).hexdigest()
    b = hashlib.sha256((candidate/filename).read_bytes()).hexdigest()
    comparisons.append({'file':filename,'baseline_sha256':a,'candidate_sha256':b,'equal':a == b})
(candidate/'capture-parity.json').write_text(json.dumps(comparisons,indent=2))
assert all(row['equal'] for row in comparisons), 'Fixed-position captures differ; inspect artifacts before acceptance'
print('All 10 frozen production-scene captures are byte-identical')
