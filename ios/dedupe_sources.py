#!/usr/bin/env python3
"""
Remove duplicate entries from Sources build phase.
Each file should only appear once.
"""

import os
import re

PROJECT_PATH = 'DoseTap.xcodeproj/project.pbxproj'

def read_project():
    with open(PROJECT_PATH, 'r') as f:
        return f.read()

def write_project(content):
    with open(PROJECT_PATH, 'w') as f:
        f.write(content)

def deduplicate_sources():
    content = read_project()
    
    # Find the Sources build phase
    sources_match = re.search(
        r'(/\* Sources \*/ = \{[^}]*isa = PBXSourcesBuildPhase;[^}]*files = \()([^)]+)(\);)',
        content, re.DOTALL
    )
    
    if not sources_match:
        print("Could not find Sources build phase")
        return
    
    prefix = sources_match.group(1)
    files_section = sources_match.group(2)
    suffix = sources_match.group(3)
    
    # Parse individual file entries
    file_entries = re.findall(r'[\t ]*([A-F0-9]{24}) /\* ([^*]+) \*/,?', files_section)
    
    print(f"Found {len(file_entries)} entries in Sources build phase")
    
    # Track seen filenames and keep only first occurrence
    seen_files = set()
    unique_entries = []
    duplicates_removed = 0
    
    for uuid, name in file_entries:
        # Extract just the filename (remove " in Sources" suffix)
        filename = name.replace(' in Sources', '').strip()
        
        if filename not in seen_files:
            seen_files.add(filename)
            unique_entries.append((uuid, name))
        else:
            duplicates_removed += 1
            print(f"  Removing duplicate: {filename}")
    
    print(f"\nRemoved {duplicates_removed} duplicate entries")
    print(f"Keeping {len(unique_entries)} unique entries")
    
    # Rebuild the files section
    new_files = '\n'
    for uuid, name in unique_entries:
        new_files += f'\t\t\t\t{uuid} /* {name} */,\n'
    new_files += '\t\t\t'
    
    # Replace in content
    new_sources = prefix + new_files + suffix
    content = content[:sources_match.start()] + new_sources + content[sources_match.end():]
    
    write_project(content)
    print("\n✅ Sources build phase deduplicated")

if __name__ == '__main__':
    os.chdir('/Users/VScode_Projects/projects/DoseTap/ios')
    deduplicate_sources()
