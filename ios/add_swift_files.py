#!/usr/bin/env python3
import uuid
import re

# Files we need to add (including Views folder files)
missing_files = [
    "EventStore.swift",
    "EventStoreAdapter.swift", 
    "UndoManager.swift",
    "TimeEngine.swift",
    "SnoozeController.swift",
    "OfflineQueue.swift",
    "AccessibilitySupport.swift",
    "DashboardView.swift",
    "DoseTapCore.swift",
    "UndoSnackbar.swift",
    "UndoStateManager.swift",  # Standalone file for UndoStateManager class
    # Views folder files
    "Views/UndoSnackbarView.swift",
    "Views/MedicationSettingsView.swift",
    "Views/MedicationPickerView.swift",
    "Views/MorningCheckInView.swift",
    "Views/PreSleepLogView.swift",
]

def generate_uuid():
    """Generate a UUID in the format used by Xcode project files"""
    return str(uuid.uuid4()).replace('-', '').upper()[:24]

def read_project_file():
    """Read the project.pbxproj file"""
    with open('DoseTap.xcodeproj/project.pbxproj', 'r') as f:
        return f.read()

def write_project_file(content):
    """Write the project.pbxproj file"""
    with open('DoseTap.xcodeproj/project.pbxproj', 'w') as f:
        f.write(content)

def add_files_to_project():
    """Add missing Swift files to the Xcode project"""
    content = read_project_file()
    
    # Find the end of PBXBuildFile section
    build_file_end = content.find('/* End PBXBuildFile section */')
    
    # Find the end of PBXFileReference section  
    file_ref_end = content.find('/* End PBXFileReference section */')
    
    # Find the children section in the group
    children_match = re.search(r'children = \(\s*(.*?)\s*\);', content, re.DOTALL)
    
    new_build_entries = []
    new_file_entries = []
    new_children_entries = []
    
    for filename in missing_files:
        build_uuid = f"AAAAAAAA{generate_uuid()[:16]}"
        file_uuid = f"AAAAAAAA{generate_uuid()[:16]}"
        
        # Create build file entry
        build_entry = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
        new_build_entries.append(build_entry)
        
        # Create file reference entry
        file_entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};'
        new_file_entries.append(file_entry)
        
        # Create children entry
        children_entry = f'\t\t\t\t{file_uuid} /* {filename} */,'
        new_children_entries.append(children_entry)
    
    # Insert build file entries
    build_insertion_point = build_file_end
    build_entries_text = '\n' + '\n'.join(new_build_entries) + '\n'
    content = content[:build_insertion_point] + build_entries_text + content[build_insertion_point:]
    
    # Update file reference end position (content has grown)
    file_ref_end = content.find('/* End PBXFileReference section */')
    
    # Insert file reference entries
    file_insertion_point = file_ref_end
    file_entries_text = '\n' + '\n'.join(new_file_entries) + '\n'
    content = content[:file_insertion_point] + file_entries_text + content[file_insertion_point:]
    
    # Find children section again and add new entries
    children_match = re.search(r'(children = \(\s*)(.*?)(\s*\);)', content, re.DOTALL)
    if children_match:
        children_start = children_match.start(2)
        children_end = children_match.end(2)
        existing_children = children_match.group(2)
        
        new_children_text = existing_children + '\n' + '\n'.join(new_children_entries)
        content = content[:children_start] + new_children_text + content[children_end:]
    
    # Find and update the sources build phase
    sources_match = re.search(r'(/* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = [^;]*;\s*files = \(\s*)(.*?)(\s*\);)', content, re.DOTALL)
    if sources_match:
        sources_start = sources_match.start(2)
        sources_end = sources_match.end(2)
        existing_sources = sources_match.group(2)
        
        new_source_entries = []
        for i, filename in enumerate(missing_files):
            build_uuid = new_build_entries[i].split()[0]
            source_entry = f'\t\t\t\t{build_uuid} /* {filename} in Sources */,'
            new_source_entries.append(source_entry)
        
        new_sources_text = existing_sources + '\n' + '\n'.join(new_source_entries)
        content = content[:sources_start] + new_sources_text + content[sources_end:]
    
    return content

if __name__ == "__main__":
    try:
        print("Adding missing Swift files to Xcode project...")
        new_content = add_files_to_project()
        write_project_file(new_content)
        print("Successfully added files to project.pbxproj")
        print("Added files:", ", ".join(missing_files))
    except Exception as e:
        print(f"Error: {e}")
