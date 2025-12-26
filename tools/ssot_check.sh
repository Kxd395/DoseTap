#!/bin/bash
# Don't exit on error - we want to collect all issues
# set -e

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
PENDING_FILE="$SSOT_DIR/PENDING_ITEMS.md"
PENDING_TEXT="$(cat "$PENDING_FILE" 2>/dev/null || true)"

COMPONENT_IDS=$(grep -o '`[a-z_]*_button`\|`[a-z_]*_display`\|`[a-z_]*_list`\|`[a-z_]*_picker`\|`[a-z_]*_chart`' "$SSOT_README" | tr -d '`' | sort -u)

for component in $COMPONENT_IDS; do
    # Check if component exists in Swift files (allowing for TODO markers)
    if ! grep -r "$component" --include="*.swift" ios/ > /dev/null 2>&1; then
        # Check if it's marked as TODO in SSOT or pending list
        if ! grep -q "TODO.*$component" "$SSOT_README" && ! echo "$PENDING_TEXT" | grep -q "$component"; then
            echo "⚠️  Component ID '$component' not found in codebase (add TODO if pending)"
            ((ERRORS++))
        fi
    fi
done

# Validate API endpoints match OpenAPI spec
echo "Checking API endpoints..."
if [ -f "$SSOT_DIR/contracts/api.openapi.yaml" ]; then
    # Extract endpoints from SSOT README
    ENDPOINTS=$(grep -E '^(POST|GET|PUT|DELETE) /' "$SSOT_README" | sed 's/.*\(POST\|GET\|PUT\|DELETE\) \(\/[^ ]*\).*/\1 \2/' | sort -u)
    
    while IFS= read -r endpoint; do
        # Skip markdown table rows that slipped through
        if echo "$endpoint" | grep -q "|"; then
            continue
        fi
        method=$(echo "$endpoint" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
        path=$(echo "$endpoint" | cut -d' ' -f2)
        
        # Skip endpoints explicitly marked TODO in SSOT or pending list
        if echo "$endpoint" | grep -qi "TODO"; then
            continue
        fi
        if echo "$PENDING_TEXT" | grep -q "$path"; then
            continue
        fi
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
    "150.*240|150-240|150–240"  # Dose window range
    "165"                        # Default target
    "never combine"              # Safety rule
    "5.*second.*undo|5s.*undo|5 seconds"    # Undo window
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

# ============================================================
# CONTRADICTION CHECKS - Added 2025-12-24, hardened 2025-12-24 session 5
# These checks ensure docs and code are aligned with SSOT
# ============================================================

echo ""
echo "🔍 Running contradiction checks..."

# Check 1: No Core Data references in non-archive docs (excluding audit logs and "why not" explanations)
# Extended patterns to catch common Core Data indicators
# Note: "core data" (lowercase) can mean "core application data", so we check specifically for:
# - "Core Data" (title case = Apple framework)
# - "CoreData" (import/class names)
# - NSPersistentContainer, NSManagedObjectContext (Core Data APIs)
# EXCEPTION: Roadmap/P2 items documenting future cleanup are allowed
echo "  Checking for Core Data references..."
COREDATA_MATCHES=$(grep -rnE "Core Data|CoreData|NSPersistentContainer|NSManagedObjectContext" docs/ ios/Core/ --include="*.md" --include="*.swift" 2>/dev/null | grep -v "archive\|Archive\|\.backup\|AUDIT_LOG\|AUDIT_REPO\|AUDIT_REPORT\|FIX_PLAN\|Why SQLite.*Not Core Data\|NO Core Data\|No Core Data\|not Core Data\|removed Core Data\|without Core Data\|deprecated.*SQLite is canonical\|didMigrateToCoreData\|Core data handling\|P2.*Remove\|Remove.*CoreData\|PersistentStore/CoreData.*Pending" || true)
if [ -n "$COREDATA_MATCHES" ]; then
    echo "❌ Found Core Data references (should be SQLite):"
    echo "$COREDATA_MATCHES" | head -5
    ((ERRORS++))
fi

# Check 2: No stale "12 event" references (should be 13, exclude audit logs which document fixes)
echo "  Checking for stale event counts..."
STALE_12_EVENTS=$(grep -rn "12 event\|12 sleep event\|12 types" docs/ ios/ --include="*.md" --include="*.swift" 2>/dev/null | grep -v "archive\|Archive\|\.backup\|AUDIT_LOG\|AUDIT_REPO\|AUDIT_REPORT\|FIX_PLAN\|SSOT_v2\.md" || true)
if [ -n "$STALE_12_EVENTS" ]; then
    echo "❌ Found stale '12 event' references (should be 13):"
    echo "$STALE_12_EVENTS" | head -5
    ((ERRORS++))
fi

# Check 3: No stale test counts (123, 95, exclude audit logs which document history)
echo "  Checking for stale test counts..."
STALE_TESTS=$(grep -rn "123 Total\|123 tests\|95 tests" docs/ --include="*.md" 2>/dev/null | grep -v "archive\|Archive\|SSOT_v2\.md\|\.backup\|AUDIT_LOG\|AUDIT_REPO\|AUDIT_REPORT\|FIX_PLAN" || true)
if [ -n "$STALE_TESTS" ]; then
    echo "❌ Found stale test counts:"
    echo "$STALE_TESTS" | head -5
    ((ERRORS++))
fi

# Check 4: Schema version consistency
echo "  Checking schema version consistency..."
SCHEMA_V2=$(grep -o "schema_version.*2\.[0-9]" docs/DATABASE_SCHEMA.md 2>/dev/null | head -1)
SSOT_SCHEMA=$(grep -o "schema_version.*2\.[0-9]" docs/SSOT/README.md 2>/dev/null | head -1)
if [ "$SCHEMA_V2" != "$SSOT_SCHEMA" ] && [ -n "$SCHEMA_V2" ] && [ -n "$SSOT_SCHEMA" ]; then
    echo "⚠️  Schema versions may differ:"
    echo "    DATABASE_SCHEMA.md: $SCHEMA_V2"
    echo "    SSOT/README.md: $SSOT_SCHEMA"
fi

# Check 5: Verify SleepEventType has 13 cases
echo "  Verifying SleepEventType case count..."
# Count only the actual SleepEventType cases (between enum declaration and next enum/struct)
EVENT_CASES=$(awk '/public enum SleepEventType/,/^}/ { if (/case [a-z]/) count++ } END { print count }' ios/Core/SleepEvent.swift 2>/dev/null || echo "0")
if [ "$EVENT_CASES" -ne "13" ] && [ "$EVENT_CASES" != "0" ]; then
    echo "⚠️  SleepEventType has $EVENT_CASES cases (expected 13)"
fi

# Check 6: Detect duplicate canonical docs outside archive
echo "  Checking for duplicate canonical docs outside archive..."
# Look for SSOT/spec files in non-canonical locations
DUP_SSOT=$(find . -name "*SSOT*.md" -not -path "./archive/*" -not -path "./docs/SSOT/*" -not -path "./.git/*" 2>/dev/null || true)
if [ -n "$DUP_SSOT" ]; then
    echo "❌ Found SSOT docs outside canonical location (should be in docs/SSOT or archived):"
    echo "$DUP_SSOT"
    ((ERRORS++))
fi

# Check for other canonical docs that should only exist in docs/ or archive/
echo "  Checking for duplicate canonical docs (PRD, architecture, etc.)..."
CANONICAL_DOCS=("PRD.md" "architecture.md" "FEATURE_ROADMAP.md" "DATABASE_SCHEMA.md")
for doc in "${CANONICAL_DOCS[@]}"; do
    DUP_DOC=$(find . -name "$doc" -not -path "./archive/*" -not -path "./docs/*" -not -path "./.git/*" 2>/dev/null || true)
    if [ -n "$DUP_DOC" ]; then
        echo "❌ Found duplicate canonical doc '$doc' outside docs/ or archive/:"
        echo "$DUP_DOC"
        ((ERRORS++))
    fi
done

# Check for markdown files in ios/ that reference Core Data (old advisory docs)
# Use title case "Core Data" to avoid false positives on "core data handling"
echo "  Checking ios/ markdown files for Core Data references..."
IOS_COREDATA_MD=$(find ./ios -name "*.md" -not -path "./archive/*" -exec grep -lE "Core Data|CoreData|NSPersistentContainer" {} \; 2>/dev/null | xargs -I{} grep -lE "Core Data|CoreData|NSPersistentContainer" {} 2>/dev/null | while read f; do
    # Exclude files that only mention it in deprecation/exclusion context
    if ! grep -qE "deprecated|SQLite is canonical|not.*Core Data|without.*Core Data|Core data handling" "$f" 2>/dev/null || grep -qE "^[^#-]*Core Data" "$f" 2>/dev/null; then
        # Check if any match is NOT in an exclusion context
        MATCHES=$(grep -nE "Core Data|CoreData|NSPersistentContainer" "$f" 2>/dev/null | grep -v "deprecated\|SQLite is canonical\|not.*Core Data\|without.*Core Data\|Core data handling")
        if [ -n "$MATCHES" ]; then
            echo "$f"
        fi
    fi
done || true)
if [ -n "$IOS_COREDATA_MD" ]; then
    echo "❌ Found markdown files in ios/ with Core Data references (should be archived):"
    echo "$IOS_COREDATA_MD"
    ((ERRORS++))
fi

# Check 7: Verify root README references canonical SSOT (HARD FAIL - source of truth guarantee)
echo "  Verifying README hierarchy..."
ROOT_README_REF=$(grep -c "docs/SSOT/README.md" README.md 2>/dev/null || echo "0")
if [ "$ROOT_README_REF" -eq "0" ]; then
    echo "❌ Root README.md does not reference docs/SSOT/README.md as canonical spec"
    echo "   This is a source-of-truth guarantee, not a style preference."
    ((ERRORS++))
fi

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
