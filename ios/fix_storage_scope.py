#!/usr/bin/env python3
import os
import uuid
import re

PROJECT_PATH = 'DoseTap.xcodeproj/project.pbxproj'

def generate_uuid():
    return str(uuid.uuid4()).replace('-', '').upper()[:24]

def add_file_to_project(filename, folder_path, rel_path):
    with open(PROJECT_PATH, 'r') as f:
        content = f.read()

    if filename in content:
        print(f"Skipping {filename}, already in project")
        return

    file_uuid = generate_uuid()
    build_uuid = generate_uuid()

    print(f"Adding {filename}...")

    # Build file entry
    build_entry = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
    
    # File reference
    file_entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel_path}"; sourceTree = "<group>"; }};'

    # 1. Add to PBXBuildFile section
    build_section_end = content.find('/* End PBXBuildFile section */')
    content = content[:build_section_end] + build_entry + '\n' + content[build_section_end:]

    # 2. Add to PBXFileReference section
    ref_section_end = content.find('/* End PBXFileReference section */')
    content = content[:ref_section_end] + file_entry + '\n' + content[ref_section_end:]

    # 3. Add to Sources build phase (main target)
    # Find the Sources build phase for DoseTap (D03)
    sources_pattern = r'(/\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \()([^)]*)(\);)'
    content = re.sub(sources_pattern, lambda m: m.group(1) + m.group(2) + f'\n\t\t\t\t{build_uuid} /* {filename} in Sources */,' + m.group(3), content, flags=re.DOTALL)

    # 4. Add to DoseTap group (F01)
    group_pattern = r'(F01 /\* DoseTap \*/ = \{.*?children = \()([^)]*)(\);)'
    content = re.sub(group_pattern, lambda m: m.group(1) + m.group(2) + f'\n\t\t\t\t{file_uuid} /* {filename} */,' + m.group(3), content, flags=re.DOTALL)

    with open(PROJECT_PATH, 'w') as f:
        f.write(content)

if __name__ == '__main__':
    os.chdir('ios')
    # Add files from FullApp that are missing in the main project but needed for tests/app
    add_file_to_project('SQLiteStorage.swift', 'FullApp', 'FullApp/SQLiteStorage.swift')
    add_file_to_project('TimelineView.swift', 'FullApp', 'FullApp/TimelineView.swift')
    add_file_to_project('QuickLogPanel.swift', 'FullApp', 'FullApp/QuickLogPanel.swift')
    add_file_to_project('MorningCheckInView.swift', 'Views', 'Views/MorningCheckInView.swift')
    add_file_to_project('TonightView.swift', 'FullApp', 'FullApp/TonightView.swift')
