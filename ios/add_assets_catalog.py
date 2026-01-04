#!/usr/bin/env python3
import re

project_file = "DoseTap.xcodeproj/project.pbxproj"

with open(project_file, 'r') as f:
    content = f.read()

# Add file reference for Assets.xcassets after Info.plist reference
assets_ref = "\t\tASSETS01 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };"

# Find the section with B03 /* Info.plist */
if "ASSETS01" not in content:
    # Add after Info.plist reference in PBXFileReference section
    content = content.replace(
        '\t\tB03 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };',
        '\t\tB03 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };\n' + assets_ref
    )
    
    # Add Assets.xcassets to the DoseTap group (after Info.plist)
    content = content.replace(
        '\t\t\t\t80A27C7D2EFAC24D0005C000 /* DoseTap.entitlements */,\n\t\t\t\tB03 /* Info.plist */,',
        '\t\t\t\t80A27C7D2EFAC24D0005C000 /* DoseTap.entitlements */,\n\t\t\t\tB03 /* Info.plist */,\n\t\t\t\tASSETS01 /* Assets.xcassets */,'
    )
    
    # Add to resources build phase
    # Find the PBXResourcesBuildPhase section
    resources_section = re.search(r'(R01 /\* Resources \*/ = \{[^}]+files = \([^)]+)', content)
    if resources_section:
        # Add build file entry for Assets.xcassets
        build_file_entry = "\t\tASSETSBUILD01 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ASSETS01 /* Assets.xcassets */; };"
        
        # Add to PBXBuildFile section
        content = content.replace(
            '/* End PBXBuildFile section */',
            build_file_entry + '\n/* End PBXBuildFile section */'
        )
        
        # Add to resources build phase
        content = re.sub(
            r'(R01 /\* Resources \*/ = \{\s+isa = PBXResourcesBuildPhase;\s+buildActionMask = \d+;\s+files = \(\s+)',
            r'\1\t\t\t\tASSETSBUILD01 /* Assets.xcassets in Resources */,\n',
            content
        )
    
    with open(project_file, 'w') as f:
        f.write(content)
    
    print("✅ Added Assets.xcassets to project")
else:
    print("⚠️  Assets.xcassets already in project")

