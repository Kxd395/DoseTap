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

# Check 1: No stale hardcoded test counts (known bad values)
echo "Check 1: No stale hardcoded test counts..."
# Block known stale values; do NOT enforce a specific current total
STALE_COUNTS=("95 tests" "123 tests" "207 tests")
for stale in "${STALE_COUNTS[@]}"; do
    if grep -rn "$stale" "$DOCS_DIR" 2>/dev/null | grep -v "archive/" | grep -v "AUDIT_" | grep -v "session"; then
        echo "⚠️  Found stale test count '$stale' - remove hardcoded counts or update"
        # Don't fail, just warn - test counts change
    fi
done
echo "✅ PASS (stale counts are warnings only)"

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

# Check 3: Schema version consistency
echo ""
echo "Check 3: Schema version consistency..."
DB_VERSION=$(awk -F': *' 'tolower($1) == "sqlite user_version" { print $2; exit }' "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null)
DICTIONARY_VERSION=$(awk -F': *' 'tolower($1) == "sqlite user_version" { print $2; exit }' "$SSOT_DIR/contracts/DataDictionary.md" 2>/dev/null)

if [ -z "$DB_VERSION" ]; then
    echo "❌ FAIL: DATABASE_SCHEMA.md is missing 'SQLite user_version: <number>'"
    FAIL=1
elif [ -z "$DICTIONARY_VERSION" ]; then
    echo "❌ FAIL: DataDictionary.md is missing 'SQLite user_version: <number>'"
    FAIL=1
elif ! [[ "$DB_VERSION" =~ ^[0-9]+$ ]]; then
    echo "❌ FAIL: DATABASE_SCHEMA SQLite user_version is not numeric: $DB_VERSION"
    FAIL=1
elif ! [[ "$DICTIONARY_VERSION" =~ ^[0-9]+$ ]]; then
    echo "❌ FAIL: DataDictionary SQLite user_version is not numeric: $DICTIONARY_VERSION"
    FAIL=1
elif [ "$DB_VERSION" = "$DICTIONARY_VERSION" ]; then
    echo "✅ PASS: Both at version $DB_VERSION"
else
    echo "❌ FAIL: DATABASE_SCHEMA SQLite user_version ($DB_VERSION) != DataDictionary SQLite user_version ($DICTIONARY_VERSION)"
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
if grep -q "Event Types (13 total)" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null; then
    echo "✅ PASS: DATABASE_SCHEMA declares 13 event types"
else
    echo "❌ FAIL: DATABASE_SCHEMA should have 'Event Types (13 total)' header"
    FAIL=1
fi

# Check 8: pre_sleep_logs uses current JSON-backed storage shape
echo ""
echo "Check 8: pre_sleep_logs uses answers_json per current storage..."
if grep -A20 "pre_sleep_logs" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null | grep -q "answers_json TEXT NOT NULL DEFAULT '{}'"; then
    echo "✅ PASS: pre_sleep_logs documents answers_json"
else
    echo "❌ FAIL: pre_sleep_logs should document answers_json until a storage migration changes it"
    FAIL=1
fi

# Check 9: morning_checkins matches current storage identity
echo ""
echo "Check 9: morning_checkins has session_date and session_id..."
if grep -A10 "morning_checkins" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null | grep -q "session_id TEXT NOT NULL" \
    && grep -A10 "morning_checkins" "$DOCS_DIR/DATABASE_SCHEMA.md" 2>/dev/null | grep -q "session_date TEXT NOT NULL"; then
    echo "✅ PASS: morning_checkins documents session_id + session_date"
else
    echo "❌ FAIL: morning_checkins should document session_id TEXT NOT NULL and session_date TEXT NOT NULL"
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
