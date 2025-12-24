#!/usr/bin/env python3
import uuid
import re

def generate_uuid():
    """Generate a UUID in the format used by Xcode project files"""
    return str(uuid.uuid4()).replace('-', '').upper()[:24]

def add_eventstore_files():
    """Add EventStore files to the Xcode project"""
    
    # Read the project file
    with open('DoseTap.xcodeproj/project.pbxproj', 'r') as f:
        content = f.read()
    
    # Files to add
    files = ["EventStore.swift", "EventStoreAdapter.swift"]
    
    # Generate UUIDs for each file
    build_uuids = []
    file_uuids = []
    
    for _ in files:
        build_uuids.append(f"AAAAAAAA{generate_uuid()[:16]}")
        file_uuids.append(f"AAAAAAAA{generate_uuid()[:16]}")
    
    # Add build file entries
    build_file_end = content.find('/* End PBXBuildFile section */')
    build_entries = []
    for i, filename in enumerate(files):
        build_entry = f'\t\t{build_uuids[i]} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuids[i]} /* {filename} */; }};'
        build_entries.append(build_entry)
    
    build_entries_text = '\n' + '\n'.join(build_entries) + '\n'
    content = content[:build_file_end] + build_entries_text + content[build_file_end:]
    
    # Add file reference entries
    file_ref_end = content.find('/* End PBXFileReference section */')
    file_entries = []
    for i, filename in enumerate(files):
        file_entry = f'\t\t{file_uuids[i]} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};'
        file_entries.append(file_entry)
    
    file_entries_text = '\n' + '\n'.join(file_entries) + '\n'
    content = content[:file_ref_end] + file_entries_text + content[file_ref_end:]
    
    # Add to children section
    children_match = re.search(r'(children = \(\s*)(.*?)(\s*\);)', content, re.DOTALL)
    if children_match:
        children_start = children_match.start(2)
        children_end = children_match.end(2)
        existing_children = children_match.group(2)
        
        children_entries = []
        for i, filename in enumerate(files):
            children_entries.append(f'\t\t\t\t{file_uuids[i]} /* {filename} */,')
        
        new_children_text = existing_children + '\n' + '\n'.join(children_entries)
        content = content[:children_start] + new_children_text + content[children_end:]
    
    # Add to sources build phase
    sources_match = re.search(r'(/* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = [^;]*;\s*files = \(\s*)(.*?)(\s*\);)', content, re.DOTALL)
    if sources_match:
        sources_start = sources_match.start(2)
        sources_end = sources_match.end(2)
        existing_sources = sources_match.group(2)
        
        source_entries = []
        for i, filename in enumerate(files):
            source_entries.append(f'\t\t\t\t{build_uuids[i]} /* {filename} in Sources */,')
        
        new_sources_text = existing_sources + '\n' + '\n'.join(source_entries)
        content = content[:sources_start] + new_sources_text + content[sources_end:]
    
    # Write the updated project file
    with open('DoseTap.xcodeproj/project.pbxproj', 'w') as f:
        f.write(content)
    
    print("Successfully added EventStore files to project")
    print("Added files:", ", ".join(files))

if __name__ == "__main__":
    try:
        add_eventstore_files()
    except Exception as e:
        print(f"Error: {e}")
