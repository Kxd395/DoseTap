#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: ripgrep (rg) is required; install it before running repository checks." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

violations=0

fail() {
  echo "FAIL: $1"
  if [[ -n "${2:-}" ]]; then
    echo "$2"
  fi
  violations=1
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! rg -q "$pattern" "$file"; then
    fail "$label" "  missing pattern in $file: $pattern"
  fi
}

SETTINGS="ios/DoseTap/SettingsStudioExport.swift"
STUDIO_MODELS="macos/DoseTapStudio/Sources/Insights/Models/InsightBundleModels.swift"
STUDIO_DETAIL="macos/DoseTapStudio/Sources/Views/NightDetail/NightDetailView.swift"
STUDIO_VALIDATOR="macos/DoseTapStudio/Sources/Import/ImportValidator.swift"
STUDIO_VALIDATOR_TESTS="macos/DoseTapStudio/Tests/ImportValidatorTests.swift"
STUDIO_IMPORTER_TESTS="macos/DoseTapStudio/Tests/ImporterTests.swift"

require_pattern "$SETTINGS" 'repo\.fetchPreSleepLog\(forSessionDate: sessionDate\)' \
  "Studio export must read pre-sleep logs through SessionRepository"
require_pattern "$SETTINGS" 'repo\.fetchMorningCheckIn\(for: sessionDate\)' \
  "Studio export must read morning check-ins through SessionRepository"
require_pattern "$SETTINGS" 'repo\.fetchCheckInSubmissions\(for: sessionDate\)' \
  "Studio export must read normalized check-in submissions through SessionRepository"
require_pattern "$SETTINGS" 'checkInSubmissions: checkInSubmissions' \
  "Studio export bundle must include normalized check-in submissions"
require_pattern "$SETTINGS" 'rawAnswersJson: encodedJSONString\(from: answers\)' \
  "Pre-sleep export must preserve the raw answer payload"

for field in \
  rawPhysicalSymptomsJson \
  rawRespiratorySymptomsJson \
  rawSleepTherapyJson \
  rawSleepEnvironmentJson \
  rawStressContextJson \
  rawTimingContextJson
do
  require_pattern "$SETTINGS" "let ${field}: String\\?" \
    "iOS export model is missing ${field}"
  require_pattern "$STUDIO_MODELS" "let ${field}: String\\?" \
    "Studio import model is missing ${field}"
  require_pattern "$STUDIO_DETAIL" "${field}" \
    "Studio detail view does not expose ${field}"
done

require_pattern "$SETTINGS" 'private struct InsightsCheckInSubmissionSummary: Codable' \
  "iOS export model is missing normalized check-in submission payload"
require_pattern "$SETTINGS" 'let responsesJson: String' \
  "iOS export model is missing normalized check-in response JSON"
require_pattern "$SETTINGS" 'writeStudioExportBundleForTesting' \
  "iOS Studio export package writer is missing DEBUG regression seam"
require_pattern "$STUDIO_MODELS" 'struct InsightCheckInSubmission: Codable' \
  "Studio import model is missing normalized check-in submission payload"
require_pattern "$STUDIO_MODELS" 'let responsesJson: String' \
  "Studio import model is missing normalized check-in response JSON"
require_pattern "$STUDIO_DETAIL" 'session\.checkInSubmissions\.sorted' \
  "Studio detail view does not expose normalized check-in submissions"
require_pattern "$STUDIO_VALIDATOR" 'Pre-sleep raw payloads missing' \
  "Studio import validation must flag missing pre-sleep raw payloads"
require_pattern "$STUDIO_VALIDATOR" 'Morning raw payload fields missing from every session' \
  "Studio import validation must flag missing morning raw payload fields"
require_pattern "$STUDIO_VALIDATOR" 'No normalized check-in submissions were imported' \
  "Studio import validation must flag missing normalized check-in submissions"

require_pattern "$STUDIO_IMPORTER_TESTS" 'testParseInsightsBundlePreservesRawCheckInPayloadsAndFractionalSleepQuality' \
  "Studio importer regression test is missing raw check-in payload coverage"
require_pattern "$STUDIO_IMPORTER_TESTS" 'rawTimingContextJson' \
  "Studio importer regression test does not cover raw morning timing context"
require_pattern "$STUDIO_IMPORTER_TESTS" 'responsesJson' \
  "Studio importer regression test does not cover normalized responses JSON"
require_pattern "$STUDIO_IMPORTER_TESTS" '4\.25' \
  "Studio importer regression test does not cover fractional morning sleep quality"
require_pattern "$STUDIO_VALIDATOR_TESTS" 'testValidatorFlagsMissingRawCheckInPayloadsAndNormalizedSubmissions' \
  "Studio validator regression test is missing old-export check-in warning coverage"
require_pattern "$STUDIO_VALIDATOR_TESTS" 'testValidatorAcceptsCurrentRawCheckInPayloadShape' \
  "Studio validator regression test is missing current-export check-in warning coverage"
require_pattern "ios/DoseTapTests/ExportTests.swift" 'writeStudioExportBundleForTesting' \
  "iOS export regression test does not verify the written Studio export package"
require_pattern "ios/DoseTapTests/ExportTests.swift" 'insights_bundle\.json' \
  "iOS export regression test does not verify insights_bundle.json"

BAD_EXPORT_HITS="$(
  rg -n 'EventStorage\\(|storage\\.fetch(CheckInSubmissions|MorningCheckIn|PreSleepLog)|checkin_submissions|responses_json|DeferredCloudKitSyncService|LegacyPersistentStore' "$SETTINGS" 2>/dev/null || true
)"
if [[ -n "$BAD_EXPORT_HITS" ]]; then
  fail "Studio check-in export is reading a non-authoritative source" "$BAD_EXPORT_HITS"
fi

if [[ "$violations" -ne 0 ]]; then
  echo ""
  echo "Check-in export must flow: check-in UI -> SessionRepository -> EventStorage -> SettingsStudioExport bundle -> DoseTapStudio."
  echo "Do not add parallel export models that drop raw payloads or bypass normalized check-in submissions."
  exit 1
fi

echo "Check-in export field guard passed"
