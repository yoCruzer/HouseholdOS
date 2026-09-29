#!/usr/bin/env python3
"""PR5 closure: isolated synthetic processes, no service/Photos/signing access."""
from pathlib import Path
import hashlib, json, subprocess, uuid

base = Path(__file__).resolve().parents[1]
run = base / 'LocalEvidence' / ('closure-process-' + str(uuid.uuid4()))
run.mkdir(parents=True)
exe = base / '.build/debug/hhos-validation'

def call(*args):
    result = subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True, timeout=45)
    (run / f'command-{len(list(run.glob("command-*.log")))}.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, (args[0], result.returncode)
    return result.stdout.strip().splitlines()[-1]

def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}

capture = run / 'capture'
assert call('prepare-preview-failure', capture) == 'EXPECTED_PREVIEW_FAILURE'
journal = json.loads(next((capture / 'journals').glob('*.json')).read_text())
for _ in range(2):
    assert json.loads(call('recover-capture', capture)) == dict(drafts=1, items=0, media=1, profiles=1, outbox=2)
for _ in range(2):
    assert json.loads(call('confirm', capture, journal['draftID'])) == dict(drafts=0, items=1, media=1, profiles=1, outbox=3)
assert hashlib.sha256((capture / 'media' / journal['originalName']).read_bytes()).hexdigest() == journal['originalHash']
assert json.loads(call('recover-capture', capture))['items'] == 1

source, clone, target = (run / name for name in ['legacy', 'clone', 'target'])
call('legacy-sync', source)
before = hashes(source)
call('migrate', source, clone)
source_id = json.loads((source / 'legacy-source-id.json').read_text())
item_id = json.loads((source / 'expected.json').read_text())['items'][0].split('|')[0]
for _ in range(2):
    assert json.loads(call('bootstrap-legacy', clone, source_id, item_id))['outbox'] == 2
partial = json.loads(call('simulate-legacy-delivery', clone, target, 1))
assert partial['pending'] == 1 and partial['barrier'] == 'PASS'
assert json.loads(call('bootstrap-legacy', clone, source_id, item_id))['outbox'] == 1
complete = json.loads(call('simulate-legacy-delivery', clone, target, 100))
assert complete['pending'] == 0 and complete['ids'] == [item_id] and complete['names'] == ['Legacy JPEG item']
assert complete['targetCounts']['items'] == 1 and complete['targetCounts']['media'] == 1
assert json.loads(call('bootstrap-legacy', clone, source_id, item_id))['outbox'] == 0
assert hashes(source) == before
summary = {'result': 'PASS', 'evidence': 'LOCAL_PLATFORM+LOGIC', 'preparedRecoverySeparateProcesses': True,
           'legacyOriginalV1SeparateProcess': True, 'legacySourceUnchanged': True, 'partialAckRestartRepeatBootstrap': True,
           'blankTargetExactlyOneItemAndMedia': True, 'barrier': 'PASS', 'liveService': 'NOT_RUN', 'photosWrites': 0,
           'relativeEvidenceDirectory': str(run.relative_to(base))}
(run / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
