#!/usr/bin/env python3

import re
import sys

def main():
    # Files required for PR-1 implementation
    pr1_files = [
        "APIClient.swift", 
        "OfflineQueue.swift",
        "ContentView.swift",
        "DoseTapCore.swift"
    ]
    
    try:
        # Read the project file
        with open('DoseTap.xcodeproj/project.pbxproj', 'r') as f:
            content = f.read()
        
        file_refs = {}
        build_refs = {}
        
        # Find PBXFileReference section
        file_ref_start = content.find('/* Begin PBXFileReference section */')
        file_ref_end = content.find('/* End PBXFileReference section */')
        
        if file_ref_start == -1 or file_ref_end == -1:
            print("Error: Could not find PBXFileReference section")
            return False
        
        # Find PBXSourcesBuildPhase section  
        sources_start = content.find('/* Begin PBXSourcesBuildPhase section */')
        sources_end = content.find('/* End PBXSourcesBuildPhase section */')
        
        if sources_start == -1 or sources_end == -1:
            print("Error: Could not find PBXSourcesBuildPhase section")
            return False
        
        # Extract existing file references to avoid duplicates
        file_ref_section = content[file_ref_start:file_ref_end]
        sources_section = content[sources_start:sources_end]
        
        # Check which files are already referenced
        existing_files = set()
        for filename in pr1_files:
            if filename in file_ref_section:
                existing_files.add(filename)
                print(f"File {filename} already exists in project")
        
        files_to_add = [f for f in pr1_files if f not in existing_files]
        
        if not files_to_add:
            print("All PR-1 files are already in the project")
            return True
        
        print(f"Adding files: {', '.join(files_to_add)}")
        
        # Generate UUIDs for the new files
        import uuid
        new_entries = []
        new_build_entries = []
        
        for filename in files_to_add:
            file_uuid = str(uuid.uuid4()).replace('-', '').upper()[:24]
            build_uuid = str(uuid.uuid4()).replace('-', '').upper()[:24]
            
            # Add file reference
            file_entry = f"\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};"
            new_entries.append(file_entry)
            
            # Add build file reference
            build_entry = f"\t\t\t\t{build_uuid} /* {filename} in Sources */,"
            new_build_entries.append(build_entry)
            
            file_refs[filename] = file_uuid
            build_refs[filename] = build_uuid
        
        # Insert new file references
        insert_pos = file_ref_end - 1
        new_file_refs = '\n'.join(new_entries) + '\n'
        content = content[:insert_pos] + new_file_refs + content[insert_pos:]
        
        # Find the files = ( section in PBXSourcesBuildPhase
        files_pattern = r'(files = \(\s*)'
        match = re.search(files_pattern, content)
        if match:
            insert_pos = match.end()
            new_build_files = '\n'.join(new_build_entries) + '\n'
            content = content[:insert_pos] + new_build_files + content[insert_pos:]
        else:
            print("Error: Could not find files section in PBXSourcesBuildPhase")
            return False
        
        # Write back to file
        with open('DoseTap.xcodeproj/project.pbxproj', 'w') as f:
            f.write(content)
        
        print("Successfully added PR-1 files to project.pbxproj")
        print(f"Added files: {', '.join(files_to_add)}")
        return True
        
    except Exception as e:
        print(f"Error modifying project file: {e}")
        return False

if __name__ == "__main__":
    main()
