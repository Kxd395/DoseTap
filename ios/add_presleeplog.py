#!/usr/bin/env python3
import uuid
import re
import os

def generate_uuid():
    return str(uuid.uuid4()).replace('-', '').upper()[:24]

def add_file_to_project():
    project_path = 'DoseTap.xcodeproj/project.pbxproj'
    
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Check if already added
    if 'PreSleepLogView.swift' in content:
        print("PreSleepLogView.swift already in project")
        return
    
    filename = "PreSleepLogView.swift"
    filepath = "Views/PreSleepLogView.swift"
    
    build_uuid = f"PSL{generate_uuid()[:21]}"
    file_uuid = f"PSL{generate_uuid()[:21]}"
    
    # Build file entry
    build_entry = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
    
    # File reference entry
    file_entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};'
    
    # Add build file entry
    build_section_end = content.find('/* End PBXBuildFile section */')
    content = content[:build_section_end] + build_entry + '\n' + content[build_section_end:]
    
    # Add file reference entry
    ref_section_end = content.find('/* End PBXFileReference section */')
    content = content[:ref_section_end] + file_entry + '\n' + content[ref_section_end:]
    
    # Add to Views group children
    views_group = re.search(r'(/\* Views \*/ = \{[^}]*children = \()([^)]*?)(\);)', content, re.DOTALL)
    if views_group:
        prefix = views_group.group(1)
        children = views_group.group(2)
        suffix = views_group.group(3)
        new_children = children.rstrip() + f'\n\t\t\t\t{file_uuid} /* {filename} */,\n\t\t\t'
        content = content[:views_group.start()] + prefix + new_children + suffix + content[views_group.end():]
    
    # Add to Sources build phase
    sources_phase = re.search(r'(/\* Sources \*/ = \{[^}]*files = \()([^)]*?)(\);)', content, re.DOTALL)
    if sources_phase:
        prefix = sources_phase.group(1)
        files = sources_phase.group(2)
        suffix = sources_phase.group(3)
        new_files = files.rstrip() + f'\n\t\t\t\t{build_uuid} /* {filename} in Sources */,\n\t\t\t'
        content = content[:sources_phase.start()] + prefix + new_files + suffix + content[sources_phase.end():]
    
    with open(project_path, 'w') as f:
        f.write(content)
    
    print(f"Added {filename} to project")

if __name__ == '__main__':
    os.chdir('/Users/VScode_Projects/projects/DoseTap/ios')
    add_file_to_project()
