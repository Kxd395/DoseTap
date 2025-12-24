#!/usr/bin/env python3
"""
Remove duplicate Swift files from build to fix 'Multiple commands produce' error.
Keeps the root versions, removes legacy duplicates from compile sources.
"""

import os
import re

PROJECT_PATH = 'DoseTap.xcodeproj/project.pbxproj'

# Files that exist in both root and legacy - remove legacy versions from build
DUPLICATE_LEGACY_FILES = [
    'SupportBundleExport.swift',
    'EnhancedSettings.swift',
    'WHOOP.swift'
]

def read_project():
    with open(PROJECT_PATH, 'r') as f:
        return f.read()

def write_project(content):
    with open(PROJECT_PATH, 'w') as f:
        f.write(content)

def remove_duplicate_builds():
    content = read_project()
    
    print("Removing duplicate legacy files from build sources...")
    
    for filename in DUPLICATE_LEGACY_FILES:
        # Find the build file entry for the legacy version (has legacy/ in path)
        # Pattern: UUID /* filename in Sources */ = {isa = PBXBuildFile; fileRef = UUID /* filename */; };
        
        # First find file references with legacy/ path
        legacy_pattern = rf'([A-F0-9]{{24}}) /\* {re.escape(filename)} \*/ = \{{isa = PBXFileReference;[^}}]*path = "legacy/{re.escape(filename)}"[^}}]*\}};'
        legacy_match = re.search(legacy_pattern, content)
        
        if legacy_match:
            legacy_file_uuid = legacy_match.group(1)
            print(f"  Found legacy {filename} with UUID {legacy_file_uuid}")
            
            # Find and remove the corresponding build file entry
            build_pattern = rf'[A-F0-9]{{24}} /\* {re.escape(filename)} in Sources \*/ = \{{isa = PBXBuildFile; fileRef = {legacy_file_uuid}[^}}]*\}};[\r\n]*'
            content, count = re.subn(build_pattern, '', content)
            if count > 0:
                print(f"    Removed build file entry")
            
            # Remove from Sources files list
            sources_pattern = rf'[\t ]*[A-F0-9]{{24}} /\* {re.escape(filename)} in Sources \*/,?[\r\n]*'
            # This is tricky - we need to find the one associated with the legacy file
            # For safety, let's just remove the file reference and let Xcode not find it
            
            # Actually, let's remove the file reference entirely for legacy duplicates
            file_ref_pattern = rf'[\t ]*{legacy_file_uuid} /\* {re.escape(filename)} \*/ = \{{[^}}]+\}};[\r\n]*'
            content, count = re.subn(file_ref_pattern, '', content)
            if count > 0:
                print(f"    Removed file reference")
            
            # Remove from group children
            child_pattern = rf'[\t ]*{legacy_file_uuid} /\* {re.escape(filename)} \*/,?[\r\n]*'
            content, count = re.subn(child_pattern, '', content)
            if count > 0:
                print(f"    Removed from group children")
        else:
            print(f"  {filename} legacy version not found in project (OK)")
    
    write_project(content)
    print("\n✅ Duplicate files removed from build")

if __name__ == '__main__':
    os.chdir('/Users/VScode_Projects/projects/DoseTap/ios')
    remove_duplicate_builds()
