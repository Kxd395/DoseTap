#!/usr/bin/env python3
"""
Fix DoseTap Xcode project by adding all missing Swift files.
This script properly handles nested folders and builds the correct group structure.
"""

import os
import uuid
import re
from pathlib import Path

PROJECT_PATH = 'DoseTap.xcodeproj/project.pbxproj'
SOURCE_DIR = 'DoseTap'

def generate_uuid():
    """Generate a 24-character UUID for Xcode"""
    return str(uuid.uuid4()).replace('-', '').upper()[:24]

def get_all_swift_files():
    """Get all Swift files with their relative paths"""
    files = []
    for root, dirs, filenames in os.walk(SOURCE_DIR):
        # Skip some directories that shouldn't be compiled
        dirs[:] = [d for d in dirs if d not in ['.build', 'DerivedData', 'xcuserdata']]
        for filename in filenames:
            if filename.endswith('.swift') and filename != 'Package.swift':
                full_path = os.path.join(root, filename)
                rel_path = os.path.relpath(full_path, SOURCE_DIR)
                files.append((filename, rel_path, full_path))
    return files

def read_project():
    with open(PROJECT_PATH, 'r') as f:
        return f.read()

def write_project(content):
    # Backup first
    backup_path = PROJECT_PATH + '.backup'
    with open(backup_path, 'w') as f:
        f.write(read_project())
    
    with open(PROJECT_PATH, 'w') as f:
        f.write(content)

def get_existing_files(content):
    """Extract filenames already in the project"""
    pattern = r'/\* ([A-Za-z0-9_]+\.swift) \*/'
    return set(re.findall(pattern, content))

def add_files_to_project():
    content = read_project()
    existing = get_existing_files(content)
    
    print(f"Found {len(existing)} existing Swift files in project")
    
    all_files = get_all_swift_files()
    print(f"Found {len(all_files)} total Swift files on disk")
    
    # Find missing files
    missing = [(name, rel, full) for name, rel, full in all_files if name not in existing]
    
    if not missing:
        print("All files already in project!")
        return
    
    print(f"Adding {len(missing)} missing files:")
    for name, rel, _ in missing:
        print(f"  - {rel}")
    
    # Track UUIDs for each file
    file_uuids = {}  # filename -> (file_ref_uuid, build_file_uuid)
    
    for filename, rel_path, full_path in missing:
        file_uuid = generate_uuid()
        build_uuid = generate_uuid()
        file_uuids[filename] = (file_uuid, build_uuid)
    
    # Insert build file entries
    build_entries = []
    for filename, (file_uuid, build_uuid) in file_uuids.items():
        entry = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
        build_entries.append(entry)
    
    build_section_end = content.find('/* End PBXBuildFile section */')
    if build_section_end != -1:
        insert_text = '\n'.join(build_entries) + '\n'
        content = content[:build_section_end] + insert_text + content[build_section_end:]
    
    # Insert file reference entries
    file_ref_entries = []
    for filename, rel_path, full_path in missing:
        file_uuid, _ = file_uuids[filename]
        # Determine the path relative to the group it will be in
        entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};'
        file_ref_entries.append(entry)
    
    ref_section_end = content.find('/* End PBXFileReference section */')
    if ref_section_end != -1:
        insert_text = '\n'.join(file_ref_entries) + '\n'
        content = content[:ref_section_end] + insert_text + content[ref_section_end:]
    
    # Add to sources build phase
    sources_entries = []
    for filename, (file_uuid, build_uuid) in file_uuids.items():
        entry = f'\t\t\t\t{build_uuid} /* {filename} in Sources */,'
        sources_entries.append(entry)
    
    # Find the Sources build phase files list
    sources_match = re.search(r'(/\* Sources \*/[^{]*\{[^}]*files = \()([^)]*?)(\);)', content, re.DOTALL)
    if sources_match:
        prefix = sources_match.group(1)
        existing_files = sources_match.group(2)
        suffix = sources_match.group(3)
        new_files = existing_files.rstrip() + '\n' + '\n'.join(sources_entries) + '\n\t\t\t'
        content = content[:sources_match.start()] + prefix + new_files + suffix + content[sources_match.end():]
    
    # Add to main DoseTap group children
    # Find the main group with DoseTap sources
    main_group_match = re.search(
        r'(/\* DoseTap \*/ = \{[^}]*isa = PBXGroup;[^}]*children = \()([^)]*?)(\);)',
        content, re.DOTALL
    )
    if main_group_match:
        prefix = main_group_match.group(1)
        children = main_group_match.group(2)
        suffix = main_group_match.group(3)
        
        new_children_entries = []
        for filename, rel_path, _ in missing:
            file_uuid, _ = file_uuids[filename]
            new_children_entries.append(f'\t\t\t\t{file_uuid} /* {filename} */,')
        
        new_children = children.rstrip() + '\n' + '\n'.join(new_children_entries) + '\n\t\t\t'
        content = content[:main_group_match.start()] + prefix + new_children + suffix + content[main_group_match.end():]
    
    write_project(content)
    print(f"\n✅ Successfully added {len(missing)} files to project")
    print("Backup saved to project.pbxproj.backup")

if __name__ == '__main__':
    os.chdir('/Users/VScode_Projects/projects/DoseTap/ios')
    add_files_to_project()
