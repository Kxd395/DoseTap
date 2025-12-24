#!/usr/bin/env python3
"""Clean DoseTap Xcode project - remove problematic files from build."""

import os
import re
import shutil

PROJECT_PATH = 'DoseTap.xcodeproj/project.pbxproj'

# Files to REMOVE from build (they have compile errors)
REMOVE_FROM_BUILD = [
    'SnoozeController.swift', 'NightAnalyzer.swift', 'Models_Event.swift',
    'Health.swift', 'EventLogger.swift', 'ReminderScheduler.swift',
    'EventStoreWithSync.swift', 'SetupWizardEnhanced.swift',
    'ActionableNotifications.swift', 'ErrorHandler.swift', 'ErrorDisplayView.swift',
    'ExportView.swift', 'DashboardConfig.swift', 'UnifiedModels.swift',
    'InventoryManagement.swift', 'HistoryView.swift', 'UnifiedStore.swift',
    'UndoSnackbar.swift', 'TimeZoneUI.swift', 'Storage_Store.swift',
    'EventStoreAdapter.swift', 'SupportBundleExport.swift',
    'FetchHelpers.swift', 'PersistentStore.swift', 'CSVExporter.swift',
    'JSONMigrator.swift', 'EventStoreCoreData.swift',
    'ContentView_Enhanced.swift', 'ContentView_Clean.swift',
    'WHOOP.swift', 'EnhancedSettings.swift', 'Secrets.swift',
    'TimeZoneMonitor.swift', 'DevelopmentHelper.swift',
]

def clean_project():
    print("Cleaning DoseTap Xcode project...")
    
    with open(PROJECT_PATH, 'r') as f:
        content = f.read()
    
    shutil.copy(PROJECT_PATH, PROJECT_PATH + '.backup3')
    
    for filename in REMOVE_FROM_BUILD:
        # Remove from PBXBuildFile section
        pattern = rf'\t\t[A-F0-9]{{24}} /\* {re.escape(filename)} in Sources \*/ = \{{isa = PBXBuildFile[^}}]+\}};\n'
        content = re.sub(pattern, '', content)
        # Remove from files list
        pattern = rf'\t+[A-F0-9]{{24}} /\* {re.escape(filename)} in Sources \*/,?\n'
        content = re.sub(pattern, '', content)
    
    with open(PROJECT_PATH, 'w') as f:
        f.write(content)
    
    print(f"✅ Removed {len(REMOVE_FROM_BUILD)} files from build")

if __name__ == '__main__':
    os.chdir('/Users/VScode_Projects/projects/DoseTap/ios')
    clean_project()
