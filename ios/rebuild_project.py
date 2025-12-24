#!/usr/bin/env python3
"""
Clean rebuild of DoseTap Xcode project file references.
Removes broken references and adds files with correct paths.
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

def read_project():
    with open(PROJECT_PATH, 'r') as f:
        return f.read()

def write_project(content):
    with open(PROJECT_PATH, 'w') as f:
        f.write(content)

def get_swift_files_by_folder():
    """Get all Swift files organized by their containing folder"""
    files_by_folder = {}
    
    for root, dirs, filenames in os.walk(SOURCE_DIR):
        dirs[:] = [d for d in dirs if d not in ['.build', 'DerivedData', 'xcuserdata']]
        
        for filename in filenames:
            if filename.endswith('.swift') and filename != 'Package.swift':
                full_path = os.path.join(root, filename)
                rel_dir = os.path.relpath(root, SOURCE_DIR)
                if rel_dir == '.':
                    rel_dir = ''
                
                if rel_dir not in files_by_folder:
                    files_by_folder[rel_dir] = []
                files_by_folder[rel_dir].append(filename)
    
    return files_by_folder

def remove_broken_references(content):
    """Remove file references that point to non-existent paths"""
    # List of files that were incorrectly added at ios/ level
    broken_files = [
        'EventStore.swift', 'EventStoreAdapter.swift', 'UndoManager.swift',
        'TimeEngine.swift', 'SnoozeController.swift', 'OfflineQueue.swift',
        'AccessibilitySupport.swift', 'DashboardView.swift', 'DoseTapCore.swift',
        'UndoSnackbar.swift', 'PreSleepLogView.swift'
    ]
    
    for filename in broken_files:
        # Remove from PBXBuildFile section
        pattern = rf'\t\t[A-Z0-9]{{24}} /\* {re.escape(filename)} in Sources \*/ = \{{[^}}]+\}};\n'
        content = re.sub(pattern, '', content)
        
        # Remove from PBXFileReference section  
        pattern = rf'\t\t[A-Z0-9]{{24}} /\* {re.escape(filename)} \*/ = \{{[^}}]+\}};\n'
        content = re.sub(pattern, '', content)
        
        # Remove from children lists
        pattern = rf'\t+[A-Z0-9]{{24}} /\* {re.escape(filename)} \*/,?\n'
        content = re.sub(pattern, '', content)
        
        # Remove from files lists
        pattern = rf'\t+[A-Z0-9]{{24}} /\* {re.escape(filename)} in Sources \*/,?\n'
        content = re.sub(pattern, '', content)
    
    return content

def get_existing_files(content):
    """Get files already properly configured in project"""
    # Match file references with proper paths
    pattern = r'/\* ([A-Za-z0-9_]+\.swift) \*/ = \{isa = PBXFileReference'
    matches = re.findall(pattern, content)
    return set(matches)

def clean_and_rebuild():
    content = read_project()
    
    print("Step 1: Removing broken file references...")
    content = remove_broken_references(content)
    
    print("Step 2: Finding files to add...")
    files_by_folder = get_swift_files_by_folder()
    existing = get_existing_files(content)
    
    print(f"  Existing files in project: {len(existing)}")
    
    # Core files that should definitely be in the project (at DoseTap root)
    core_files = [
        'ContentView.swift', 'DoseTapApp.swift', 'SettingsView.swift',
        'UserSettingsManager.swift', 'ContentView_Enhanced.swift',
        'ContentView_Clean.swift', 'SupportBundleExport.swift',
        'WHOOP.swift', 'EnhancedSettings.swift', 'Secrets.swift'
    ]
    
    # Files in subfolders
    subfolder_files = {
        'Storage': ['EventStorage.swift', 'JSONMigrator.swift', 'EventStoreCoreData.swift'],
        'Views': ['MorningCheckInView.swift', 'PreSleepLogView.swift'],
        'Foundation': ['TimeZoneMonitor.swift', 'DevelopmentHelper.swift'],
        'Persistence': ['PersistentStore.swift', 'FetchHelpers.swift'],
        'Export': ['CSVExporter.swift'],
    }
    
    # Legacy files (these exist but may have conflicts - add them anyway)
    legacy_files = [
        'SnoozeController.swift', 'NightAnalyzer.swift', 'Models_Event.swift',
        'Health.swift', 'EventLogger.swift', 'ReminderScheduler.swift',
        'EventStoreWithSync.swift', 'SupportBundleExport.swift',
        'SetupWizardEnhanced.swift', 'ActionableNotifications.swift',
        'ErrorHandler.swift', 'ErrorDisplayView.swift', 'ExportView.swift',
        'DashboardConfig.swift', 'UnifiedModels.swift', 'InventoryManagement.swift',
        'HistoryView.swift', 'UnifiedStore.swift', 'UndoSnackbar.swift',
        'TimeZoneUI.swift', 'Storage_Store.swift', 'EventStoreAdapter.swift'
    ]
    
    files_to_add = []
    
    # Check core files
    for filename in core_files:
        if filename not in existing:
            path = os.path.join(SOURCE_DIR, filename)
            if os.path.exists(path):
                files_to_add.append((filename, '', path))
    
    # Check subfolder files
    for folder, files in subfolder_files.items():
        for filename in files:
            if filename not in existing:
                path = os.path.join(SOURCE_DIR, folder, filename)
                if os.path.exists(path):
                    files_to_add.append((filename, folder, path))
    
    # Check legacy files
    for filename in legacy_files:
        if filename not in existing:
            path = os.path.join(SOURCE_DIR, 'legacy', filename)
            if os.path.exists(path):
                files_to_add.append((filename, 'legacy', path))
    
    if not files_to_add:
        print("  No files to add")
        write_project(content)
        return
    
    print(f"  Adding {len(files_to_add)} files:")
    for name, folder, _ in files_to_add:
        loc = f"{folder}/" if folder else ""
        print(f"    - {loc}{name}")
    
    # Generate UUIDs and add entries
    for filename, folder, filepath in files_to_add:
        file_uuid = generate_uuid()
        build_uuid = generate_uuid()
        
        # Build file entry
        build_entry = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
        
        # File reference with correct path
        if folder:
            file_entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{folder}/{filename}"; sourceTree = "<group>"; }};'
        else:
            file_entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};'
        
        # Add build file entry
        build_section_end = content.find('/* End PBXBuildFile section */')
        content = content[:build_section_end] + build_entry + '\n' + content[build_section_end:]
        
        # Add file reference entry
        ref_section_end = content.find('/* End PBXFileReference section */')
        content = content[:ref_section_end] + file_entry + '\n' + content[ref_section_end:]
        
        # Add to sources build phase
        sources_match = re.search(r'(/\* Sources \*/[^{]*\{[^}]*files = \()([^)]*?)(\);)', content, re.DOTALL)
        if sources_match:
            prefix = sources_match.group(1)
            files_list = sources_match.group(2)
            suffix = sources_match.group(3)
            new_entry = f'\n\t\t\t\t{build_uuid} /* {filename} in Sources */,'
            content = content[:sources_match.start()] + prefix + files_list.rstrip() + new_entry + '\n\t\t\t' + suffix + content[sources_match.end():]
        
        # Add to main DoseTap group
        main_group = re.search(r'(/\* DoseTap \*/ = \{[^}]*isa = PBXGroup;[^}]*children = \()([^)]*?)(\);)', content, re.DOTALL)
        if main_group:
            prefix = main_group.group(1)
            children = main_group.group(2)
            suffix = main_group.group(3)
            new_child = f'\n\t\t\t\t{file_uuid} /* {filename} */,'
            content = content[:main_group.start()] + prefix + children.rstrip() + new_child + '\n\t\t\t' + suffix + content[main_group.end():]
    
    write_project(content)
    print(f"\n✅ Project file updated successfully")

if __name__ == '__main__':
    os.chdir('/Users/VScode_Projects/projects/DoseTap/ios')
    clean_and_rebuild()
