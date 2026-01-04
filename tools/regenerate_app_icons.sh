#!/bin/bash
# Regenerate DoseTap App Icons from SVG source
# This script uses the liquid glass window design to create all required icon sizes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICON_SOURCE_DIR="$PROJECT_ROOT/docs/icon/dosetap-liquid-glass-window"
ICON_OUTPUT_DIR="$PROJECT_ROOT/ios/DoseTap/Assets.xcassets/AppIcon.appiconset"

echo "🎨 DoseTap App Icon Generator"
echo "=============================="
echo ""
echo "Source: $ICON_SOURCE_DIR"
echo "Output: $ICON_OUTPUT_DIR"
echo ""

# Check if ImageMagick/rsvg-convert is installed
if ! command -v rsvg-convert &> /dev/null; then
    echo "❌ Error: rsvg-convert not found"
    echo ""
    echo "Please install librsvg:"
    echo "  brew install librsvg"
    echo ""
    exit 1
fi

if ! command -v convert &> /dev/null; then
    echo "❌ Error: ImageMagick convert not found"
    echo ""
    echo "Please install ImageMagick:"
    echo "  brew install imagemagick"
    echo ""
    exit 1
fi

# Create temp directory for compositing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "📦 Creating temporary working directory: $TEMP_DIR"
echo ""

# Define all required icon sizes
declare -A ICON_SIZES=(
    ["icon-20@1x"]=20
    ["icon-20@2x"]=40
    ["icon-20@3x"]=60
    ["icon-29@1x"]=29
    ["icon-29@2x"]=58
    ["icon-29@3x"]=87
    ["icon-40@1x"]=40
    ["icon-40@2x"]=80
    ["icon-40@3x"]=120
    ["icon-60@2x"]=120
    ["icon-60@3x"]=180
    ["icon-76@1x"]=76
    ["icon-76@2x"]=152
    ["icon-83.5@2x"]=167
    ["icon-1024"]=1024
)

# Function to composite SVG layers and generate PNG
generate_icon() {
    local name=$1
    local size=$2
    
    echo "  Generating ${name}.png (${size}x${size})..."
    
    # Convert each SVG layer to PNG at target size
    rsvg-convert -w $size -h $size \
        "$ICON_SOURCE_DIR/dosetap-liquid-glass-window-bg.svg" \
        -o "$TEMP_DIR/bg.png"
    
    rsvg-convert -w $size -h $size \
        "$ICON_SOURCE_DIR/dosetap-liquid-glass-window-fg2.svg" \
        -o "$TEMP_DIR/fg2.png"
    
    rsvg-convert -w $size -h $size \
        "$ICON_SOURCE_DIR/dosetap-liquid-glass-window-fg1.svg" \
        -o "$TEMP_DIR/fg1.png"
    
    # Composite layers: bg + fg2 + fg1
    convert "$TEMP_DIR/bg.png" \
        "$TEMP_DIR/fg2.png" -composite \
        "$TEMP_DIR/fg1.png" -composite \
        "$ICON_OUTPUT_DIR/${name}.png"
}

echo "🖼️  Generating app icons..."
echo ""

# Generate all icon sizes
for icon_name in "${!ICON_SIZES[@]}"; do
    size="${ICON_SIZES[$icon_name]}"
    generate_icon "$icon_name" "$size"
done

echo ""
echo "✅ All app icons generated successfully!"
echo ""
echo "📱 Next steps:"
echo "  1. Clean build in Xcode: Product → Clean Build Folder (Cmd+Shift+K)"
echo "  2. Delete app from simulator/device"
echo "  3. Rebuild and run"
echo "  4. The new icon should appear on the home screen"
echo ""
