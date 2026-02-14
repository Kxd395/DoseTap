#!/usr/bin/env bash
set -euo pipefail

echo "Running tab split-brain guard..."

URL_ROUTER_FILE="ios/DoseTap/URLRouter.swift"
CONTENT_VIEW_FILE="ios/DoseTap/ContentView.swift"
TESTS_FILE="ios/DoseTapTests/URLRouterAndNavigationTests.swift"

if ! grep -q "static let navigationDeepLinks" "$URL_ROUTER_FILE"; then
  echo "❌ Missing AppTab.navigationDeepLinks in $URL_ROUTER_FILE"
  exit 1
fi

if ! grep -q "AppTab.tab(forDeepLinkHost: host)" "$URL_ROUTER_FILE"; then
  echo "❌ URLRouter is not using AppTab.tab(forDeepLinkHost:) in $URL_ROUTER_FILE"
  exit 1
fi

if ! grep -q "test_navigationDeepLinkContract_isStable" "$TESTS_FILE"; then
  echo "❌ Missing navigation contract test in $TESTS_FILE"
  exit 1
fi

if ! grep -q "AppTab.navigationDeepLinks.map" "$TESTS_FILE"; then
  echo "❌ NavigationFlowTests is not using AppTab.navigationDeepLinks in $TESTS_FILE"
  exit 1
fi

BAD_PATTERNS="$(grep -nE '\.tag\((0|1|2|3|4)\)|selectedTab[[:space:]]*=[[:space:]]*(0|1|2|3|4)|handleNavigate\(tab:[[:space:]]*(0|1|2|3|4)\)' "$URL_ROUTER_FILE" "$CONTENT_VIEW_FILE" "$TESTS_FILE" || true)"
if [ -n "$BAD_PATTERNS" ]; then
  echo "❌ Raw tab indices detected in canonical router/content/tests files:"
  echo "$BAD_PATTERNS"
  exit 1
fi

echo "✅ Tab split-brain guard passed"
