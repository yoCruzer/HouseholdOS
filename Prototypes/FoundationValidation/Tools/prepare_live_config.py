#!/usr/bin/env python3
"""Owner-run read-only inspection of an already signed validation App. Creates no Apple resources."""
from pathlib import Path
import argparse,hashlib,json,plistlib,subprocess,uuid
p=argparse.ArgumentParser()
p.add_argument('--app',type=Path,required=True)
p.add_argument('--container',required=True)
p.add_argument('--library',type=uuid.UUID,required=True)
p.add_argument('--role',choices=['source','blankReplica'],required=True)
p.add_argument('--zone',help='Existing registered source zone for blank replica; omit for a new source namespace')
p.add_argument('--authorize-development-test',action='store_true',required=True)
p.add_argument('--output',type=Path,default=Path('LocalEvidence/live-config.json'))
a=p.parse_args()
subprocess.run(['codesign','--verify','--strict',str(a.app)],check=True,capture_output=True)
raw=subprocess.run(['codesign','-d','--entitlements',':-',str(a.app)],check=True,capture_output=True).stdout
entitlements=plistlib.loads(raw[raw.index(b'<?xml'):])
info=plistlib.loads((a.app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.yocruzer.householdos.foundationvalidation'
assert entitlements.get('com.apple.developer.icloud-container-environment')=='Development'
assert a.container in entitlements.get('com.apple.developer.icloud-container-identifiers',[])
assert 'CloudKit' in entitlements.get('com.apple.developer.icloud-services',[])
assert entitlements.get('aps-environment')=='development'
if a.role=='blankReplica': assert a.zone, 'Second endpoint must use the registered source zone'
zone=a.zone or 'HHOSVAL_'+str(uuid.uuid4()).upper()
assert zone.startswith('HHOSVAL_') and uuid.UUID(zone[8:])
config={'program':'HHOS-FAV-001','containerID':a.container,'environment':'Development','metadataZone':zone,'libraryID':str(a.library).upper(),'role':a.role,'newNamespaceAuthorized':a.zone is None,'bundleID':info['CFBundleIdentifier'],'codeSHA256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [a.app/info['CFBundleExecutable'],*sorted(a.app.glob('*.dylib'))]},'signedEntitlementsVerified':True,'ownerAuthorized':True}
a.output.parent.mkdir(parents=True,exist_ok=True)
assert not a.output.exists(), 'Do not overwrite existing run registration/config'
a.output.write_text(json.dumps(config,indent=2)+'\n')
print('Verified existing signed Development artifact; private config written. No Developer Portal or CloudKit resource was created.')
