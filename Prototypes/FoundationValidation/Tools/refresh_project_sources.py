#!/usr/bin/env python3
"""Keep the standalone Xcode target on the same core source list as SwiftPM."""
from pathlib import Path
import hashlib,re
base=Path(__file__).resolve().parents[1]
def uid(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
p=base/'FoundationValidation.xcodeproj/project.pbxproj'
s=p.read_text()
files=sorted([str(f.relative_to(base)) for f in (base/'Sources/ValidationCore').rglob('*.swift')]+[str(f.relative_to(base)) for f in (base/'App').rglob('*.swift')])
added=[]
for file in files:
    if uid('file'+file)+' = ' not in s:
        added += [f'{uid("file"+file)} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{file}"; sourceTree = SOURCE_ROOT; }};',f'{uid("build"+file)} = {{isa = PBXBuildFile; fileRef = {uid("file"+file)}; }};']
s=s.replace('objects = {\n','objects = {\n'+'\n'.join(added)+'\n')
s=re.sub(r'('+uid('group')+r' = \{isa = PBXGroup; children = \()[^)]*',lambda m:m[1]+','.join(uid('file'+f) for f in files)+','+uid('product')+',',s)
s=re.sub(r'('+uid('sources')+r' = \{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = \()[^)]*',lambda m:m[1]+','.join(uid('build'+f) for f in files)+',',s)
p.write_text(s)
