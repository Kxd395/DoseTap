#!/bin/bash
# Generate DoseTap icon sets from Liquid Glass SVG layers
# Requires: rsvg-convert (librsvg)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ICON_SRC="$PROJECT_ROOT/docs/icon/dosetap-liquid-glass-window"
ASSETS_DIR="$PROJECT_ROOT/ios/DoseTap/Assets.xcassets"
WATCH_ASSETS_DIR="$PROJECT_ROOT/watchos/DoseTapWatch/Assets.xcassets"

# Temp directory for compositing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "🎨 Generating DoseTap icons from Liquid Glass SVG..."
echo "   Source: $ICON_SRC"

# Create composite SVG (all layers merged)
cat > "$TEMP_DIR/composite.svg" << 'SVGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#0D1D3F"/>
      <stop offset="55%" stop-color="#0B1022"/>
      <stop offset="100%" stop-color="#070816"/>
    </linearGradient>
    <radialGradient id="h" cx="50%" cy="25%" r="72%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.06"/>
      <stop offset="65%" stop-color="#000000" stop-opacity="0"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.16"/>
    </radialGradient>
  </defs>

  <!-- Background -->
  <rect x="0" y="0" width="1024" height="1024" fill="url(#bg)"/>
  <rect x="0" y="0" width="1024" height="1024" fill="url(#h)"/>

  <!-- Foreground 2 (ticks) -->
  <g transform="translate(512,512)">
    <g stroke="#F2F7FF" stroke-width="18" stroke-linecap="round" opacity="0.35">
      <path d="M 0 -290 L 0 -250"/>
      <path d="M 145 -251 L 125 -218"/>
      <path d="M 251 -145 L 218 -125"/>
      <path d="M 290 28 L 250 28"/>
      <path d="M 251 201 L 218 181"/>
      <path d="M 145 307 L 125 274"/>
      <path d="M 0 346 L 0 306"/>
      <path d="M -145 307 L -125 274"/>
      <path d="M -251 201 L -218 181"/>
      <path d="M -290 28 L -250 28"/>
      <path d="M -251 -145 L -218 -125"/>
      <path d="M -145 -251 L -125 -218"/>
    </g>
  </g>

  <!-- Foreground 1 (ring + arc) -->
  <g transform="translate(512,512)">
    <circle cx="0" cy="28" r="300" fill="none" stroke="#F2F7FF" stroke-width="56" opacity="0.14"/>
    <path d="M -290 28 A 290 290 0 0 1 290 28" fill="none" stroke="#34D3C7" stroke-width="56" stroke-linecap="round" opacity="0.95"/>
    <circle cx="0" cy="28" r="176" fill="#F2F7FF" opacity="0.18"/>
    <circle cx="0" cy="28" r="124" fill="#F2F7FF" opacity="0.24"/>
  </g>
</svg>
SVGEOF

generate_icon() {
    local size=$1
    local output=$2
    rsvg-convert -w "$size" -h "$size" "$TEMP_DIR/composite.svg" -o "$output"
}

# Create iOS AppIcon.appiconset
echo "📱 Creating iOS App Icon set..."
IOS_ICON_DIR="$ASSETS_DIR/AppIcon.appiconset"
mkdir -p "$IOS_ICON_DIR"

# Generate Contents.json for iOS
cat > "$IOS_ICON_DIR/Contents.json" << 'JSONEOF'
{
  "images" : [
    {
      "filename" : "icon-20@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-20@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-29@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-29@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-40@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-40@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-60@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-60@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-20@2x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-20@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-29@2x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-29@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-40@2x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-40@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-76.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76"
    },
    {
      "filename" : "icon-76@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76"
    },
    {
      "filename" : "icon-83.5@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "83.5x83.5"
    },
    {
      "filename" : "icon-1024.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSONEOF

# Generate iOS icons
echo "   Generating icon-20@2x.png (40x40)"
generate_icon 40 "$IOS_ICON_DIR/icon-20@2x.png"

echo "   Generating icon-20@3x.png (60x60)"
generate_icon 60 "$IOS_ICON_DIR/icon-20@3x.png"

echo "   Generating icon-29@2x.png (58x58)"
generate_icon 58 "$IOS_ICON_DIR/icon-29@2x.png"

echo "   Generating icon-29@3x.png (87x87)"
generate_icon 87 "$IOS_ICON_DIR/icon-29@3x.png"

echo "   Generating icon-40@2x.png (80x80)"
generate_icon 80 "$IOS_ICON_DIR/icon-40@2x.png"

echo "   Generating icon-40@3x.png (120x120)"
generate_icon 120 "$IOS_ICON_DIR/icon-40@3x.png"

echo "   Generating icon-60@2x.png (120x120)"
generate_icon 120 "$IOS_ICON_DIR/icon-60@2x.png"

echo "   Generating icon-60@3x.png (180x180)"
generate_icon 180 "$IOS_ICON_DIR/icon-60@3x.png"

echo "   Generating icon-76.png (76x76)"
generate_icon 76 "$IOS_ICON_DIR/icon-76.png"

echo "   Generating icon-76@2x.png (152x152)"
generate_icon 152 "$IOS_ICON_DIR/icon-76@2x.png"

echo "   Generating icon-83.5@2x.png (167x167)"
generate_icon 167 "$IOS_ICON_DIR/icon-83.5@2x.png"

echo "   Generating icon-1024.png (1024x1024)"
generate_icon 1024 "$IOS_ICON_DIR/icon-1024.png"

# Create watchOS AppIcon.appiconset
echo "⌚ Creating watchOS App Icon set..."
WATCH_ICON_DIR="$WATCH_ASSETS_DIR/AppIcon.appiconset"
mkdir -p "$WATCH_ICON_DIR"

# Generate Contents.json for watchOS
cat > "$WATCH_ICON_DIR/Contents.json" << 'JSONEOF'
{
  "images" : [
    {
      "filename" : "watch-24@2x.png",
      "idiom" : "watch",
      "role" : "notificationCenter",
      "scale" : "2x",
      "size" : "24x24",
      "subtype" : "38mm"
    },
    {
      "filename" : "watch-27.5@2x.png",
      "idiom" : "watch",
      "role" : "notificationCenter",
      "scale" : "2x",
      "size" : "27.5x27.5",
      "subtype" : "42mm"
    },
    {
      "filename" : "watch-33@2x.png",
      "idiom" : "watch",
      "role" : "notificationCenter",
      "scale" : "2x",
      "size" : "33x33",
      "subtype" : "45mm"
    },
    {
      "filename" : "watch-29@2x.png",
      "idiom" : "watch",
      "role" : "companionSettings",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "watch-29@3x.png",
      "idiom" : "watch",
      "role" : "companionSettings",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "watch-40@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "40x40",
      "subtype" : "38mm"
    },
    {
      "filename" : "watch-44@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "44x44",
      "subtype" : "40mm"
    },
    {
      "filename" : "watch-46@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "46x46",
      "subtype" : "41mm"
    },
    {
      "filename" : "watch-50@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "50x50",
      "subtype" : "44mm"
    },
    {
      "filename" : "watch-51@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "51x51",
      "subtype" : "45mm"
    },
    {
      "filename" : "watch-54@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "54x54",
      "subtype" : "49mm"
    },
    {
      "filename" : "watch-86@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "86x86",
      "subtype" : "38mm"
    },
    {
      "filename" : "watch-98@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "98x98",
      "subtype" : "42mm"
    },
    {
      "filename" : "watch-108@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "108x108",
      "subtype" : "44mm"
    },
    {
      "filename" : "watch-117@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "117x117",
      "subtype" : "45mm"
    },
    {
      "filename" : "watch-129@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "129x129",
      "subtype" : "49mm"
    },
    {
      "filename" : "watch-1024.png",
      "idiom" : "watch-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSONEOF

# Generate watchOS icons
echo "   Generating watch-24@2x.png (48x48)"
generate_icon 48 "$WATCH_ICON_DIR/watch-24@2x.png"

echo "   Generating watch-27.5@2x.png (55x55)"
generate_icon 55 "$WATCH_ICON_DIR/watch-27.5@2x.png"

echo "   Generating watch-29@2x.png (58x58)"
generate_icon 58 "$WATCH_ICON_DIR/watch-29@2x.png"

echo "   Generating watch-29@3x.png (87x87)"
generate_icon 87 "$WATCH_ICON_DIR/watch-29@3x.png"

echo "   Generating watch-33@2x.png (66x66)"
generate_icon 66 "$WATCH_ICON_DIR/watch-33@2x.png"

echo "   Generating watch-40@2x.png (80x80)"
generate_icon 80 "$WATCH_ICON_DIR/watch-40@2x.png"

echo "   Generating watch-44@2x.png (88x88)"
generate_icon 88 "$WATCH_ICON_DIR/watch-44@2x.png"

echo "   Generating watch-46@2x.png (92x92)"
generate_icon 92 "$WATCH_ICON_DIR/watch-46@2x.png"

echo "   Generating watch-50@2x.png (100x100)"
generate_icon 100 "$WATCH_ICON_DIR/watch-50@2x.png"

echo "   Generating watch-51@2x.png (102x102)"
generate_icon 102 "$WATCH_ICON_DIR/watch-51@2x.png"

echo "   Generating watch-54@2x.png (108x108)"
generate_icon 108 "$WATCH_ICON_DIR/watch-54@2x.png"

echo "   Generating watch-86@2x.png (172x172)"
generate_icon 172 "$WATCH_ICON_DIR/watch-86@2x.png"

echo "   Generating watch-98@2x.png (196x196)"
generate_icon 196 "$WATCH_ICON_DIR/watch-98@2x.png"

echo "   Generating watch-108@2x.png (216x216)"
generate_icon 216 "$WATCH_ICON_DIR/watch-108@2x.png"

echo "   Generating watch-117@2x.png (234x234)"
generate_icon 234 "$WATCH_ICON_DIR/watch-117@2x.png"

echo "   Generating watch-129@2x.png (258x258)"
generate_icon 258 "$WATCH_ICON_DIR/watch-129@2x.png"

echo "   Generating watch-1024.png (1024x1024)"
generate_icon 1024 "$WATCH_ICON_DIR/watch-1024.png"

echo ""
echo "✅ Icon generation complete!"
echo "   iOS icons:     $IOS_ICON_DIR"
echo "   watchOS icons: $WATCH_ICON_DIR"
echo ""
echo "📝 Note: For iOS 26 Liquid Glass support, use Xcode's Icon Composer"
echo "   to import the layered SVGs from: $ICON_SRC"
