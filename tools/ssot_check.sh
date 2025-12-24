#!/bin/bash
set -e

echo "🔍 DoseTap SSOT Integrity Check v1.1"
echo "====================================="

SSOT_DIR="docs/SSOT"
SSOT_README="$SSOT_DIR/README.md"
ERRORS=0

# Check SSOT folder exists
if [ ! -d "$SSOT_DIR" ]; then
    echo "❌ SSOT folder not found at $SSOT_DIR"
    exit 1
fi

if [ ! -f "$SSOT_README" ]; then
    echo "❌ SSOT README not found at $SSOT_README"
    exit 1
fi

# Check for legacy files that should be redirected
echo "Checking for legacy files..."
LEGACY_FILES=(
    "docs/SSOT.md"
    "docs/SSOT_NAV.md"
)

for file in "${LEGACY_FILES[@]}"; do
    if [ -f "$file" ]; then
        if ! grep -q "MOVED TO" "$file"; then
            echo "⚠️  Legacy file $file exists but does not contain redirection notice"
            ((ERRORS++))
        fi
    fi
done

# Check component IDs referenced in SSOT exist in codebase
echo "Checking component IDs..."
COMPONENT_IDS=$(grep -o '`[a-z_]*_button`\|`[a-z_]*_display`\|`[a-z_]*_list`\|`[a-z_]*_picker`\|`[a-z_]*_chart`' "$SSOT_README" | tr -d '`' | sort -u)

for component in $COMPONENT_IDS; do
    # Check if component exists in Swift files (allowing for TODO markers)
    if ! grep -r "$component" --include="*.swift" ios/ > /dev/null 2>&1; then
        # Check if it's marked as TODO in SSOT
        if ! grep -q "TODO.*$component" "$SSOT_README"; then
            echo "⚠️  Component ID '$component' not found in codebase (add TODO if pending)"
            ((ERRORS++))
        fi
    fi
done

# Validate API endpoints match OpenAPI spec
echo "Checking API endpoints..."
if [ -f "$SSOT_DIR/contracts/api.openapi.yaml" ]; then
    # Extract endpoints from SSOT README
    ENDPOINTS=$(grep -E '(POST|GET|PUT|DELETE) /' "$SSOT_README" | sed 's/.*\(POST\|GET\|PUT\|DELETE\) \(\/[^ ]*\).*/\1 \2/' | sort -u)
    
    while IFS= read -r endpoint; do
        method=$(echo "$endpoint" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
        path=$(echo "$endpoint" | cut -d' ' -f2)
        
        # Check if endpoint exists in OpenAPI spec
        if ! grep -q "$path:" "$SSOT_DIR/contracts/api.openapi.yaml"; then
            echo "⚠️  Endpoint '$endpoint' not in OpenAPI spec"
            ((ERRORS++))
        fi
    done <<< "$ENDPOINTS"
else
    echo "⚠️  OpenAPI spec not found at $SSOT_DIR/contracts/api.openapi.yaml"
    ((ERRORS++))
fi

# Check for broken internal links in SSOT
echo "Checking internal links..."
find "$SSOT_DIR" -name "*.md" | while read -r file; do
    # Extract markdown links
    grep -o '\[.*\]([^)]*\.md[^)]*)' "$file" 2>/dev/null | while read -r link; do
        # Extract just the path from the link
        link_path=$(echo "$link" | sed 's/.*](\([^)#]*\).*/\1/')
        
        # Skip external links
        if [[ "$link_path" == http* ]]; then
            continue
        fi
        
        # Resolve relative path
        if [[ "$link_path" == /* ]]; then
            target="$link_path"
        else
            target="$(dirname "$file")/$link_path"
        fi
        
        # Normalize path
        target=$(realpath --relative-to=. "$target" 2>/dev/null || echo "$target")
        
        if [ ! -f "$target" ] && [ ! -f "$(echo $target | sed 's/#.*//')" ]; then
            echo "⚠️  Broken link in $(basename $file): $link_path"
            ((ERRORS++))
        fi
    done
done

# Validate required SSOT sections exist
echo "Checking required SSOT sections..."
REQUIRED_SECTIONS=(
    "## Core Invariants"
    "## Application Architecture"
    "## Button Logic & Components"
    "## API Contract"
    "## Data Models"
    "## Planner"
    "## Accessibility"
    "## Glossary"
    "## Definition of Done"
)

for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -q "$section" "$SSOT_README"; then
        echo "❌ Missing required section: $section"
        ((ERRORS++))
    fi
done

# Check JSON schemas are valid
echo "Checking JSON schemas..."
if command -v python3 > /dev/null 2>&1; then
    for schema in "$SSOT_DIR"/contracts/schemas/*.json; do
        if [ -f "$schema" ]; then
            python3 -m json.tool "$schema" > /dev/null 2>&1 || {
                echo "❌ Invalid JSON in $(basename $schema)"
                ((ERRORS++))
            }
        fi
    done
else
    echo "⚠️  Python3 not found, skipping JSON validation"
fi

# Check that critical safety constraints are documented
echo "Checking safety constraints..."
SAFETY_PATTERNS=(
    "150.*240\|150-240\|150–240"  # Dose window range
    "165"                          # Default target
    "never combine"                # Safety rule
    "5.*second.*undo\|5s.*undo"    # Undo window
)

for pattern in "${SAFETY_PATTERNS[@]}"; do
    if ! grep -iE "$pattern" "$SSOT_README" > /dev/null; then
        echo "❌ Safety constraint not found: $pattern"
        ((ERRORS++))
    fi
done

# Additional check - verify mermaid diagrams exist
echo "Checking mermaid diagrams..."
DIAGRAM_DIR="$SSOT_DIR/contracts/diagrams"
if [ -d "$DIAGRAM_DIR" ]; then
    if [ ! "$(ls -A $DIAGRAM_DIR)" ]; then
        echo "⚠️  Diagrams directory is empty"
        ((ERRORS++))
    fi
else
    echo "⚠️  Diagrams directory not found"
    ((ERRORS++))
fi

# Summary
echo ""
echo "====================================="
if [ $ERRORS -eq 0 ]; then
    echo "✅ SSOT integrity check PASSED!"
    echo "All components, endpoints, and sections verified."
else
    echo "❌ SSOT integrity check FAILED!"
    echo "Found $ERRORS issues that need attention."
    exit 1
fi

echo ""
echo "📊 Stats:"
echo "  - Component IDs found: $(echo "$COMPONENT_IDS" | wc -w)"
echo "  - Required sections: ${#REQUIRED_SECTIONS[@]}"
echo "  - Safety patterns checked: ${#SAFETY_PATTERNS[@]}"
echo ""
echo "Last checked: $(date)"
