#!/bin/bash
# Regenerate DoseTap App Icons from SVG source (macOS native version)
# Uses rsvg-convert and native macOS sips for compositing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICON_SOURCE_DIR="$PROJECT_ROOT/docs/icon/dosetap-liquid-glass-window"
ICON_OUTPUT_DIR="$PROJECT_ROOT/ios/DoseTap/Assets.xcassets/AppIcon.appiconset"

echo "🎨 DoseTap App Icon Generator (macOS Native)"
echo "============================================="
echo ""
echo "Source: $ICON_SOURCE_DIR"
echo "Output: $ICON_OUTPUT_DIR"
echo ""

# Check if rsvg-convert is installed
if ! command -v rsvg-convert &> /dev/null; then
    echo "❌ Error: rsvg-convert not found"
    echo ""
    echo "Please install librsvg:"
    echo "  brew install librsvg"
    echo ""
    exit 1
fi

# Create temp directory for compositing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "📦 Creating temporary working directory: $TEMP_DIR"
echo ""

# Define all required icon sizes
declare -a ICON_NAMES=(
    "icon-20@1x" "icon-20@2x" "icon-20@3x"
    "icon-29@1x" "icon-29@2x" "icon-29@3x"
    "icon-40@1x" "icon-40@2x" "icon-40@3x"
    "icon-60@2x" "icon-60@3x"
    "icon-76@1x" "icon-76@2x"
    "icon-83.5@2x"
    "icon-1024"
)

declare -a ICON_SIZES=(
    20 40 60
    29 58 87
    40 80 120
    120 180
    76 152
    167
    1024
)

# Function to composite SVG layers using Python PIL
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
    
    # Use Python to composite layers with proper alpha blending
    python3 << EOF
from PIL import Image

# Open layers
bg = Image.open("$TEMP_DIR/bg.png").convert("RGBA")
fg2 = Image.open("$TEMP_DIR/fg2.png").convert("RGBA")
fg1 = Image.open("$TEMP_DIR/fg1.png").convert("RGBA")

# Composite: bg + fg2 + fg1
result = Image.alpha_composite(bg, fg2)
result = Image.alpha_composite(result, fg1)

# Save final result
result.save("$ICON_OUTPUT_DIR/${name}.png")
EOF
}

echo "🖼️  Generating app icons..."
echo ""

# Check if PIL/Pillow is available
if ! python3 -c "from PIL import Image" 2>/dev/null; then
    echo "❌ Error: Python Pillow (PIL) not found"
    echo ""
    echo "Please install Pillow:"
    echo "  pip3 install Pillow"
    echo ""
    exit 1
fi

# Generate all icon sizes
for i in "${!ICON_NAMES[@]}"; do
    icon_name="${ICON_NAMES[$i]}"
    size="${ICON_SIZES[$i]}"
    generate_icon "$icon_name" "$size"
done

echo ""
echo "✅ All app icons generated successfully!"
echo ""
echo "📱 Next steps:"
echo "  1. In Xcode: Product → Clean Build Folder (Cmd+Shift+K)"
echo "  2. Delete DoseTap app from simulator/device"
echo "  3. Build and run (Cmd+R)"
echo "  4. The new icon should appear on the home screen"
echo ""
