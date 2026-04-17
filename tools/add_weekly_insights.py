#!/usr/bin/env python3
"""One-shot: add WeeklyInsightsCard.swift to Xcode project."""
import uuid, re, sys, os

PROJ = "ios/DoseTap.xcodeproj/project.pbxproj"
FN = "WeeklyInsightsCard.swift"

with open(PROJ) as f:
    content = f.read()

if FN in content:
    print("already present")
    sys.exit(0)

def gid():
    return uuid.uuid4().hex.upper()[:24]

bid, fid = gid(), gid()

content = content.replace(
    "/* End PBXBuildFile section */",
    f"\t\t{bid} /* {FN} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {FN} */; }};\n/* End PBXBuildFile section */",
)
content = content.replace(
    "/* End PBXFileReference section */",
    f'\t\t{fid} /* {FN} */ = {{isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = {FN}; sourceTree = "<group>"; }};\n/* End PBXFileReference section */',
)

m = re.search(r"([A-F0-9]{24} /\* TonightView\.swift \*/,)", content)
if not m:
    print("ERR: no TonightView anchor in group children")
    sys.exit(1)
content = content[: m.end()] + f"\n\t\t\t\t{fid} /* {FN} */," + content[m.end():]

m2 = re.search(r"([A-F0-9]{24} /\* TonightView\.swift in Sources \*/,)", content)
if not m2:
    print("ERR: no TonightView Sources anchor")
    sys.exit(1)
content = content[: m2.end()] + f"\n\t\t\t\t{bid} /* {FN} in Sources */," + content[m2.end():]

with open(PROJ, "w") as f:
    f.write(content)

print(f"added {FN}")
