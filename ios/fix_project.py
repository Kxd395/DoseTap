#!/usr/bin/env python3
import re

def fix_project_file():
    """Fix the project file by moving the new files to the correct group"""
    
    # Read the project file
    with open('DoseTap.xcodeproj/project.pbxproj', 'r') as f:
        content = f.read()
    
    # Files that were added incorrectly
    files_to_move = [
        'AAAAAAAA29284E4EC5484B02 /* EventStore.swift */',
        'AAAAAAAAC540E3CED5564202 /* EventStoreAdapter.swift */',
        'AAAAAAAAE0F22F85FEFD4CEF /* UndoManager.swift */',
        'AAAAAAAAF8DBB46EA6BA4AF4 /* TimeEngine.swift */',
        'AAAAAAAA5FFA2A9605084735 /* SnoozeController.swift */',
        'AAAAAAAADC78EED6FBFA40C7 /* OfflineQueue.swift */',
        'AAAAAAAA8D015C0089B4473F /* AccessibilitySupport.swift */',
        'AAAAAAAAEE27FE58AB4A42BF /* DashboardView.swift */',
        'AAAAAAAA0CC9FCE3385840E0 /* DoseTapCore.swift */',
        'AAAAAAAAAFE84BED89DE4FEB /* UndoSnackbar.swift */'
    ]
    
    # Remove the files from the root group (after the Products group)
    for file_ref in files_to_move:
        # Find and remove from root group children
        pattern = r'(\s+AAAAAAAA0000000000000401,\s*\n)(\s+' + re.escape(file_ref) + r',\s*\n)'
        content = re.sub(pattern, r'\1', content)
        
        # Also try removing with different spacing patterns
        pattern = r'(\s+)' + re.escape(file_ref) + r',\s*\n'
        match = re.search(pattern, content)
        if match:
            # Find if this is in the root group section
            # Look for context around the match
            start = max(0, match.start() - 200)
            context = content[start:match.start()]
            
            # Check if this is in the root group (should have AAAAAAAA0000000000000401 nearby)
            if 'AAAAAAAA0000000000000401' in context:
                content = content[:match.start()] + content[match.end():]
    
    # Find the DoseTap group and add the files there
    dosetap_group_pattern = r'(AAAAAAAA0000000000000500 /\* DoseTap \*/ = \{\s*isa = PBXGroup;\s*children = \(\s*.*?)(AAAAAAAA000000000000020B /\* WHOOP\.swift \*/,\s*)'
    
    def add_files_to_dosetap_group(match):
        before_whoop = match.group(1)
        whoop_line = match.group(2)
        
        # Add our files before WHOOP.swift
        new_files = []
        for file_ref in files_to_move:
            new_files.append(f'        {file_ref},')
        
        new_content = before_whoop + '\n'.join(new_files) + '\n        ' + whoop_line
        return new_content
    
    content = re.sub(dosetap_group_pattern, add_files_to_dosetap_group, content, flags=re.DOTALL)
    
    # Write the fixed project file
    with open('DoseTap.xcodeproj/project.pbxproj', 'w') as f:
        f.write(content)
    
    print("Fixed project file structure")

if __name__ == "__main__":
    try:
        fix_project_file()
        print("Successfully moved files to DoseTap group")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
