#!/usr/bin/env bash
# Release Preflight — automated enforcement of RELEASE_CHECKLIST.md gates.
# Run before tagging any release:
#   bash tools/release_preflight.sh [vX.Y.Z]
#
# Also runs as part of CI on tag pushes (ci.yml → release-pinning-check).
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}✅ PASS:${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}❌ FAIL:${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}⚠️  WARN:${NC} $1"; WARN=$((WARN + 1)); }

TAG="${1:-}"
echo "═══════════════════════════════════════════"
echo " DoseTap Release Preflight"
echo "═══════════════════════════════════════════"
echo ""

# ─── 1. Tag format ───────────────────────────────────────────────
if [[ -n "$TAG" ]]; then
  if [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    pass "Tag format valid: $TAG"
  else
    fail "Tag format invalid: $TAG (expected vX.Y.Z or vX.Y.Z-beta.N)"
  fi
else
  warn "No tag provided — skipping tag format check"
fi

# ─── 2. SSOT integrity ──────────────────────────────────────────
if [[ -f "tools/ssot_check.sh" ]]; then
  if bash tools/ssot_check.sh >/dev/null 2>&1; then
    pass "SSOT integrity check"
  else
    fail "SSOT integrity check — run 'bash tools/ssot_check.sh' for details"
  fi
else
  warn "tools/ssot_check.sh not found — skipping SSOT check"
fi

# ─── 3. No tracked secrets ──────────────────────────────────────
if git ls-files --error-unmatch ios/DoseTap/Secrets.swift >/dev/null 2>&1; then
  fail "ios/DoseTap/Secrets.swift is tracked in git — must be .gitignored"
else
  pass "Secrets.swift not tracked"
fi

# Check for hardcoded credentials in source
CRED_HITS="$(
  git grep -nE '(whoopClient(ID|Secret)|apiKey|authToken)[[:space:]]*=[[:space:]]*"[^"]{8,}"' \
    -- ios/DoseTap ios/Core 2>/dev/null \
  | grep -Ev 'Secrets\.template\.swift|SecureConfig\.swift|\.md$' \
  | grep -Ev 'YOUR_|DOSETAP_|TODO|REPLACE|example|""' || true
)"
if [[ -n "$CRED_HITS" ]]; then
  fail "Potential hardcoded credentials found:\n$CRED_HITS"
else
  pass "No hardcoded credentials in source"
fi

# ─── 4. Certificate pin validation ──────────────────────────────
if [[ -n "${DOSETAP_CERT_PINS:-}" ]]; then
  if CONFIGURATION=Release bash tools/validate_release_pins.sh >/dev/null 2>&1; then
    pass "Certificate pin validation (≥2 unique valid pins)"
  else
    fail "Certificate pin validation — run 'CONFIGURATION=Release bash tools/validate_release_pins.sh'"
  fi
else
  warn "DOSETAP_CERT_PINS not set — pin validation skipped (required for Release tags)"
fi

# ─── 5. Mock transport not in production ─────────────────────────
MOCK_LEAKS="$(
  awk '
    /#if DEBUG/ { debug_depth += 1 }
    /#endif/ { if (debug_depth > 0) debug_depth -= 1 }
    /MockAPITransport/ && debug_depth == 0 && $0 !~ /\/\/ MARK/ {
      print FILENAME ":" FNR ":" $0
    }
  ' ios/Core/*.swift 2>/dev/null || true
)"
if [[ -n "$MOCK_LEAKS" ]]; then
  fail "MockAPITransport found outside #if DEBUG in ios/Core:\n$MOCK_LEAKS"
else
  pass "MockAPITransport confined to #if DEBUG"
fi

# ─── 6. CHANGELOG updated ───────────────────────────────────────
if [[ -n "$TAG" && -f "CHANGELOG.md" ]]; then
  VERSION="${TAG#v}"  # Strip leading 'v'
  if grep -qF "$VERSION" CHANGELOG.md; then
    pass "CHANGELOG.md mentions version $VERSION"
  else
    fail "CHANGELOG.md has no entry for $VERSION — update before tagging"
  fi
elif [[ -z "$TAG" ]]; then
  warn "No tag provided — skipping CHANGELOG version check"
else
  warn "CHANGELOG.md not found — skipping version check"
fi

# ─── 7. SwiftPM builds ──────────────────────────────────────────
if swift build >/dev/null 2>&1; then
  pass "SwiftPM build (DoseCore)"
else
  fail "SwiftPM build failed — run 'swift build' for details"
fi

# ─── 8. SwiftPM tests ───────────────────────────────────────────
if swift test >/dev/null 2>&1; then
  pass "SwiftPM tests"
else
  fail "SwiftPM tests failed — run 'swift test' for details"
fi

# ─── Summary ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo -e " Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
echo "═══════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo -e "${RED}Release blocked — fix failures before tagging.${NC}"
  exit 1
fi

if [[ "$WARN" -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}Warnings present — review before proceeding.${NC}"
fi

echo ""
echo -e "${GREEN}All preflight checks passed. Safe to tag release.${NC}"
exit 0
