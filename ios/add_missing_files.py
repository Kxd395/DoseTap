#!/usr/bin/env python3
"""
Add missing Swift files to the DoseTap Xcode project.
Run from the ios/ directory.
"""
import uuid
import re
import os

# Files from ios/DoseTap/ that need to be in the DoseTap target
# NOTE: SleepEvent.swift, TimeEngine.swift, UnifiedSleepSession.swift are in Core package, not here
MISSING_FILES = [
    "UserSettingsManager.swift",
    "SettingsView.swift",
    "ErrorHandler.swift",
    "EventLogger.swift",
    "ActionableNotifications.swift",
    "Health.swift",
    "WHOOP.swift",
    "HistoryView.swift",
    "ExportView.swift",
    "UndoSnackbar.swift",
    "SnoozeController.swift",
    "ReminderScheduler.swift",
    "NightAnalyzer.swift",
    "UnifiedModels.swift",
    "UnifiedStore.swift",
    "EventStoreAdapter.swift",
    "EventStoreWithSync.swift",
    "InventoryManagement.swift",
    "EnhancedSettings.swift",
    "SetupWizardEnhanced.swift",
    "TimeZoneUI.swift",
    "DashboardConfig.swift",
    "ErrorDisplayView.swift",
    "Storage_Store.swift",
    "SupportBundleExport.swift",
    "Models_Event.swift",
]

def generate_uuid():
    """Generate a 24-char UUID for Xcode project files"""
    return uuid.uuid4().hex.upper()[:24]

def read_project_file(path):
    with open(path, 'r') as f:
        return f.read()

def write_project_file(path, content):
    with open(path, 'w') as f:
        f.write(content)

def get_existing_files(content):
    """Extract already-referenced Swift files from the project"""
    pattern = r'/\* (\w+\.swift) \*/'
    return set(re.findall(pattern, content))

def add_files_to_project(content, files_to_add):
    """Add Swift files to the Xcode project"""
    
    build_entries = []
    file_ref_entries = []
    children_entries = []
    source_entries = []
    
    for filename in files_to_add:
        build_uuid = generate_uuid()
        file_uuid = generate_uuid()
        
        # PBXBuildFile entry
        build_entries.append(
            f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
        )
        
        # PBXFileReference entry
        file_ref_entries.append(
            f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};'
        )
        
        # Group children entry
        children_entries.append(f'\t\t\t\t{file_uuid} /* {filename} */,')
        
        # Sources build phase entry
        source_entries.append(f'\t\t\t\t{build_uuid} /* {filename} in Sources */,')
    
    # Insert PBXBuildFile entries
    build_end = content.find('/* End PBXBuildFile section */')
    if build_end != -1:
        insert_text = '\n'.join(build_entries) + '\n'
        content = content[:build_end] + insert_text + content[build_end:]
    
    # Insert PBXFileReference entries
    file_ref_end = content.find('/* End PBXFileReference section */')
    if file_ref_end != -1:
        insert_text = '\n'.join(file_ref_entries) + '\n'
        content = content[:file_ref_end] + insert_text + content[file_ref_end:]
    
    # Insert into DoseTap group children
    # Find the F01 /* DoseTap */ group and its children
    group_pattern = r'(F01 /\* DoseTap \*/ = \{\s*isa = PBXGroup;\s*children = \()([^)]*?)(\);)'
    match = re.search(group_pattern, content, re.DOTALL)
    if match:
        existing_children = match.group(2)
        new_children = existing_children.rstrip() + '\n' + '\n'.join(children_entries) + '\n\t\t\t'
        content = content[:match.start(2)] + new_children + content[match.end(2):]
    
    # Insert into Sources build phase
    sources_pattern = r'(J01 /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = \d+;\s*files = \()([^)]*?)(\);)'
    match = re.search(sources_pattern, content, re.DOTALL)
    if match:
        existing_sources = match.group(2)
        new_sources = existing_sources.rstrip() + '\n' + '\n'.join(source_entries) + '\n\t\t\t'
        content = content[:match.start(2)] + new_sources + content[match.end(2):]
    
    return content

def main():
    project_path = 'DoseTap.xcodeproj/project.pbxproj'
    
    if not os.path.exists(project_path):
        print(f"Error: {project_path} not found. Run from ios/ directory.")
        return 1
    
    print("Reading project file...")
    content = read_project_file(project_path)
    
    # Check which files already exist
    existing = get_existing_files(content)
    print(f"Found {len(existing)} existing Swift files in project")
    
    # Filter to files that aren't already in the project
    files_to_add = [f for f in MISSING_FILES if f not in existing]
    
    if not files_to_add:
        print("All files already in project!")
        return 0
    
    print(f"\nAdding {len(files_to_add)} missing files:")
    for f in files_to_add:
        print(f"  + {f}")
    
    # Backup original
    backup_path = project_path + '.backup'
    write_project_file(backup_path, content)
    print(f"\nBackup saved to {backup_path}")
    
    # Add files
    new_content = add_files_to_project(content, files_to_add)
    write_project_file(project_path, new_content)
    
    print(f"\n✅ Successfully added {len(files_to_add)} files to project!")
    print("\nReopen the project in Xcode to see changes.")
    return 0

if __name__ == "__main__":
    exit(main())
