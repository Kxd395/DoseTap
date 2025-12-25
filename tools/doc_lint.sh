#!/bin/bash
# DoseTap Documentation Drift Lint
# Fails CI if critical contradictions exist
#
# Run: ./tools/doc_lint.sh
# Exit codes: 0 = pass, 1 = fail

set -e

FAIL=0
DOCS_DIR="docs"
SSOT_DIR="docs/SSOT"

echo "=== DoseTap Doc Lint ==="
echo ""

# Check 1: No "123 tests" anywhere (stale count)
echo "Check 1: No stale '123 tests' references..."
if grep -rn "123 tests" "$DOCS_DIR" 2>/dev/null | grep -v "AUDIT_"; then
    echo "❌ FAIL: Found '123 tests' - update to 207"
    FAIL=1
else
    echo "✅ PASS"
fi

# Check 2: No "12 event" or "12 types" (stale event count)
echo ""
echo "Check 2: No stale '12 event' or '12 types' references..."
# Exclude archive folder and audit reports (historical)
if grep -rn --include="*.md" "12 event\|12 types" "$DOCS_DIR" 2>/dev/null | grep -v "archive/" | grep -v "AUDIT_"; then
    echo "❌ FAIL: Found '12 event/types' - update to 13"
    FAIL=1
else
    echo "✅ PASS"
fi

# Check 3: No "95 tests" (stale count)
echo ""
echo "Check 3: No stale '95 tests' references (except archive)..."
if grep -rn "95 tests" "$DOCS_DIR" 2>/dev/null | grep -v "archive/" | grep -v "SSOT_v2.md" | grep -v "AUDIT_"; then
    echo "❌ FAIL: Found '95 tests' - update to 207"
    FAIL=1
else
    echo "✅ PASS"
fi

# Check 4: DATABASE_SCHEMA version matches SchemaEvolution
echo ""
echo "Check 4: Schema version consistency..."
DB_VERSION=$(grep -m1 "Version:" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)
EVOLUTION_VERSION=$(grep -m1 "Current Schema Version" "$SSOT_DIR/contracts/SchemaEvolution.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)

if [ "$DB_VERSION" = "$EVOLUTION_VERSION" ]; then
    echo "✅ PASS: Both at version $DB_VERSION"
else
    echo "❌ FAIL: DATABASE_SCHEMA version ($DB_VERSION) != SchemaEvolution version ($EVOLUTION_VERSION)"
    FAIL=1
fi

# Check 5: No Core Data references in architecture.md (except negation)
echo ""
echo "Check 5: No Core Data as implementation in architecture.md..."
# Look for Core Data being used as implementation, ignore "No Core Data" negations
if grep -n "Core Data\|NSPersistentContainer\|NSManagedObject" "$DOCS_DIR/architecture.md" 2>/dev/null | grep -v "NO Core Data\|Not Core Data\|No Core Data\|Why SQLite"; then
    echo "❌ FAIL: Found Core Data references - should be SQLite only"
    FAIL=1
else
    echo "✅ PASS"
fi

# Check 6: Canonical sleep event count is 13
echo ""
echo "Check 6: constants.json has 13 sleep event types..."
SLEEP_TYPES=$(grep -c '"rawValue"' "$SSOT_DIR/constants.json" 2>/dev/null || echo "0")
if [ "$SLEEP_TYPES" = "13" ]; then
    echo "✅ PASS: 13 sleep event types in constants.json"
else
    echo "❌ FAIL: Expected 13 sleep event types, found $SLEEP_TYPES"
    FAIL=1
fi

# Check 7: DATABASE_SCHEMA has 13 event types in taxonomy
echo ""
echo "Check 7: DATABASE_SCHEMA sleep_events taxonomy has 13 types..."
# Count rows in the Event Types table (lines with wire format)
TAXONOMY_COUNT=$(grep -c "^\| \`" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null | head -1 || echo "0")
# Alternative: check for the header saying 13
if grep -q "Event Types (13 total)" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null; then
    echo "✅ PASS: DATABASE_SCHEMA declares 13 event types"
else
    echo "❌ FAIL: DATABASE_SCHEMA should have 'Event Types (13 total)' header"
    FAIL=1
fi

# Check 8: pre_sleep_logs uses session_date identity (not answers_json design)
echo ""
echo "Check 8: pre_sleep_logs uses structured columns (not answers_json)..."
if grep -A20 "pre_sleep_logs" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null | grep -q "caffeine_cups"; then
    echo "✅ PASS: pre_sleep_logs uses structured columns"
else
    echo "❌ FAIL: pre_sleep_logs should use structured columns (caffeine_cups, etc)"
    FAIL=1
fi

# Check 9: morning_checkins uses session_date as UNIQUE identity
echo ""
echo "Check 9: morning_checkins uses session_date UNIQUE identity..."
if grep -A10 "morning_checkins" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null | grep -q "session_date TEXT NOT NULL UNIQUE"; then
    echo "✅ PASS: morning_checkins uses session_date UNIQUE"
else
    echo "❌ FAIL: morning_checkins should have session_date TEXT NOT NULL UNIQUE"
    FAIL=1
fi

echo ""
echo "=== Summary ==="
if [ $FAIL -eq 0 ]; then
    echo "✅ All checks passed"
    exit 0
else
    echo "❌ Some checks failed - fix before merging"
    exit 1
fi
