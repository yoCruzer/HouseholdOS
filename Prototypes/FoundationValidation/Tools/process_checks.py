#!/usr/bin/env python3
"""Synthetic process-crash evidence. Never accepts arbitrary user-data roots."""
from pathlib import Path
import hashlib, json, os, selectors, signal, subprocess, time, uuid, sqlite3, plistlib, shutil

base = Path(__file__).resolve().parents[1]
run = base / 'LocalEvidence' / ('process-' + str(uuid.uuid4()))
run.mkdir(parents=True, exist_ok=False)
exe = base / '.build/debug/hhos-validation'
results = []

def digest_tree(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}

def execute(*args, check=True):
    result = subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True, timeout=30)
    index = len(list(run.glob('command-*.log')))
    (run / f'command-{index}.log').write_text(result.stdout + result.stderr)
    if check and result.returncode:
        raise RuntimeError(f'CLI failed with exit {result.returncode}; see local evidence')
    return result

for phase in ['prepared', 'committed', 'originalFinalized']:
    root = run / phase
    process = subprocess.Popen([str(exe), 'crash-capture', str(root), phase], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    poller = selectors.DefaultSelector(); poller.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 20
    reached = False
    while time.monotonic() < deadline:
        if process.poll() is not None:
            break
        for key, _ in poller.select(timeout=0.25):
            line = os.read(key.fileobj.fileno(), 4096)
            if ('CHECKPOINT ' + phase).encode() in line:
                reached = True
                break
        if reached:
            break
    if not reached:
        process.kill(); process.wait()
        raise RuntimeError(f'checkpoint not reached: {phase}')
    process.kill(); code = process.wait(timeout=5)
    assert code == -signal.SIGKILL
    journal = json.loads(next((root / 'journals').glob('*.json')).read_text())
    recovered = execute('recover-capture', root)
    counts = json.loads(recovered.stdout.strip().splitlines()[-1])
    committed = phase != 'prepared'
    assert counts['drafts'] == int(committed) and counts['outbox'] == (2 if committed else 0)
    original = root / ('media' if committed else 'staging') / journal['originalName']
    assert hashlib.sha256(original.read_bytes()).hexdigest() == journal['originalHash']
    results.append({'case': phase, 'termination': 'SIGKILL', 'exit': code, 'counts': counts, 'originalHashPreserved': True})

# Generate an immutable true baseline store in a terminated process, including WAL/SHM if present.
legacy = run / 'legacy'
execute('legacy', legacy)
before = digest_tree(legacy)
clone = run / 'candidate'
execute('migrate', legacy, clone)
execute('verify', clone)
execute('verify', clone)
assert digest_tree(legacy) == before
# Observable historical entity identity is taken from the actual store metadata.
probe = run / 'identity-probe'
shutil.copytree(legacy, probe)
connection = sqlite3.connect(f'file:{probe / "library.store"}?mode=ro', uri=True)
metadata = plistlib.loads(connection.execute('SELECT Z_PLIST FROM Z_METADATA').fetchone()[0])
connection.close()
assert digest_tree(legacy) == before
versions = metadata.get('NSStoreModelVersionHashes', {})
assert set(versions) == {'ItemRecord', 'CaptureDraftRecord', 'MediaAssetRecord', 'CategoryRecord', 'LocationRecord'}
results.append({'case':'legacy-clone-migrate-reopen-repeat', 'status':'PASS', 'sourceImmutable':True,
                'legacyEntities': {key: value.hex() for key,value in versions.items()}, 'sourceFileHashes':before})
# A corrupt synthetic clone must fail without replacing the store or touching its source.
corrupt = run / 'corrupt-candidate'
shutil.copytree(legacy, corrupt)
store = corrupt / 'library.store'
store.write_bytes(b'not-a-sqlite-store' + store.read_bytes()[18:])
corrupt_hash = hashlib.sha256(store.read_bytes()).hexdigest()
failure = execute('verify', corrupt, check=False)
assert failure.returncode != 0
assert store.exists() and hashlib.sha256(store.read_bytes()).hexdigest() == corrupt_hash
assert digest_tree(legacy) == before
assert execute('migrate', legacy, clone, check=False).returncode != 0
assert digest_tree(legacy) == before
results.append({'case':'corrupt-clone-and-existing-destination', 'status':'PASS', 'sourceImmutable':True, 'corruptStoreNotReplaced':True})
summary = {'program':'HHOS-FAV-001', 'evidenceLevel':'LOCAL_PLATFORM', 'results':results,
           'relativeEvidenceDirectory':str(run.relative_to(base))}
(run / 'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
