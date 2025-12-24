#!/bin/bash

# Script to add new Swift files to DoseTap Xcode project
# This addresses the integration issue where new components can't be found during compilation

echo "Adding new Swift files to DoseTap Xcode project..."

cd "$(dirname "$0")"

# Files to add to the project
FILES=(
    "EventStore.swift"
    "OfflineQueue.swift" 
    "TimeEngine.swift"
    "SnoozeController.swift"
    "UndoManager.swift"
    "UndoSnackbar.swift"
    "TimeEngineTests.swift"
    "SnoozeControllerTests.swift"
    "UndoManagerTests.swift"
)

echo "Files to be added:"
for file in "${FILES[@]}"; do
    if [ -f "DoseTap/$file" ]; then
        echo "  ✓ $file (exists)"
    else
        echo "  ✗ $file (missing)"
    fi
done

echo ""
echo "MANUAL STEPS REQUIRED:"
echo "1. Open DoseTap.xcodeproj in Xcode"
echo "2. Right-click on the DoseTap folder in the navigator"
echo "3. Select 'Add Files to DoseTap...'"
echo "4. Select all the files listed above"
echo "5. Ensure 'Copy items if needed' is unchecked (files are already in place)"
echo "6. Ensure 'Add to target: DoseTap' is checked"
echo "7. Click 'Add'"
echo ""
echo "After adding files, the project should build successfully with all components integrated."

# Alternative: Try using pbxproj tool if available
if command -v pbxproj &> /dev/null; then
    echo "pbxproj tool found - attempting automatic addition..."
    cd DoseTap.xcodeproj
    for file in "${FILES[@]}"; do
        if [ -f "../DoseTap/$file" ]; then
            pbxproj file -t DoseTap "../DoseTap/$file"
            echo "Added $file to project"
        fi
    done
else
    echo "pbxproj tool not available. Manual addition required."
fi
