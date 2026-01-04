#!/bin/bash
# Install DoseTap to a connected iPhone for testing
# Usage: ./install_to_device.sh

set -e

echo "🔍 Searching for connected devices..."
DEVICE_ID=$(xcrun xctrace list devices 2>&1 | grep -i "iphone" | grep -v "Simulator" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

if [ -z "$DEVICE_ID" ]; then
    echo "❌ No iPhone connected via USB"
    echo ""
    echo "Please connect your iPhone and:"
    echo "  1. Unlock your iPhone"
    echo "  2. Trust this computer when prompted"
    echo "  3. Run this script again"
    exit 1
fi

echo "✅ Found iPhone: $DEVICE_ID"
echo ""

cd "$(dirname "$0")/../ios"

echo "🔨 Building for device..."
xcodebuild clean build \
    -project DoseTap.xcodeproj \
    -scheme DoseTap \
    -destination "id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    CODE_SIGN_IDENTITY="Apple Development" \
    DEVELOPMENT_TEAM="" \
    | grep -E "BUILD|error:" | tail -5

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build succeeded!"
    echo ""
    echo "📱 The app should now be installed on your iPhone"
    echo ""
    echo "⚠️  First-time setup:"
    echo "   1. On your iPhone, go to: Settings > General > VPN & Device Management"
    echo "   2. Tap your Apple ID under 'Developer App'"
    echo "   3. Tap 'Trust [Your Name]'"
    echo "   4. The app will now launch"
    echo ""
    echo "🎉 DoseTap is ready for testing!"
else
    echo ""
    echo "❌ Build failed. Check the output above for errors."
    exit 1
fi
