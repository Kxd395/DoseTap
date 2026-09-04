#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

assert_max_lines() {
  local file_name="$1"
  local maximum="$2"
  local actual

  [[ -f "$file_name" ]] || fail "required architecture component is missing: $file_name"
  actual="$(wc -l < "$file_name" | tr -d ' ')"
  (( actual <= maximum )) || fail "$file_name grew to $actual lines (migration ceiling: $maximum)"
}

time_math_files="$(find ios -type f -name 'TimeIntervalMath.swift' -print | sort)"
[[ "$time_math_files" == "ios/Core/TimeIntervalMath.swift" ]] || {
  printf '%s\n' "$time_math_files" >&2
  fail "TimeIntervalMath must have exactly one source file under ios/Core"
}

time_math_definitions="$(rg -n '^(public )?(enum|struct|class) TimeIntervalMath\b' ios --glob '*.swift' || true)"
[[ "$(printf '%s\n' "$time_math_definitions" | sed '/^$/d' | wc -l | tr -d ' ')" == "1" ]] \
  || fail "TimeIntervalMath must have exactly one type definition"
[[ "$time_math_definitions" == ios/Core/TimeIntervalMath.swift:* ]] \
  || fail "the canonical TimeIntervalMath definition moved outside DoseCore"

if grep -q 'TimeIntervalMath.swift' ios/DoseTap.xcodeproj/project.pbxproj; then
  fail "the phone target must consume DoseCore.TimeIntervalMath, not compile a local copy"
fi

[[ -f Tests/DoseCoreTests/TimeIntervalMathCharacterizationTests.swift ]] \
  || fail "canonical time math characterization tests are missing"
grep -q 'TimeIntervalMathCharacterizationTests.swift' Package.swift \
  || fail "canonical time math characterization tests are absent from the explicit SwiftPM test list"

assert_max_lines macos/DoseTapStudio/Sources/Insights/Models/InsightModels.swift 1600
assert_max_lines macos/DoseTapStudio/Sources/Insights/Models/InsightBundleModels.swift 850
assert_max_lines ios/DoseTap/SettingsActions.swift 100
assert_max_lines ios/DoseTap/SettingsStudioExport.swift 1800
assert_max_lines ios/DoseTap/Storage/SessionRepository.swift 1450
assert_max_lines ios/DoseTap/Storage/SessionRepositoryPresentation.swift 200
assert_max_lines ios/DoseTap/Storage/SessionRepositoryDoseEventMetadata.swift 100
assert_max_lines ios/DoseTap/Views/MorningCheckInSections.swift 300
assert_max_lines ios/DoseTap/Views/MorningCheckInDoseAndFunctioningSections.swift 350
assert_max_lines ios/DoseTap/Views/MorningCheckInClinicalSections.swift 700
assert_max_lines ios/DoseTap/Storage/EventStorage+CheckInSubmissions.swift 300
assert_max_lines ios/DoseTap/Storage/EventStorage+SymptomEvents.swift 900

rg -q '^struct InsightBundle:' macos/DoseTapStudio/Sources/Insights/Models/InsightBundleModels.swift \
  || fail "Studio transport models are not owned by InsightBundleModels.swift"
! rg -q '^struct InsightBundle:' macos/DoseTapStudio/Sources/Insights/Models/InsightModels.swift \
  || fail "Studio transport models leaked back into InsightModels.swift"

rg -q '^    func exportData\(\)' ios/DoseTap/SettingsStudioExport.swift \
  || fail "Studio export orchestration is missing from SettingsStudioExport.swift"
! rg -q '^    func exportData\(\)' ios/DoseTap/SettingsActions.swift \
  || fail "Studio export orchestration leaked back into SettingsActions.swift"

rg -q '^struct MorningCheckInClinicalContextSection:' ios/DoseTap/Views/MorningCheckInClinicalSections.swift \
  || fail "clinical check-in UI is not owned by MorningCheckInClinicalSections.swift"
rg -q '^struct MorningCheckInDoseReconciliationSection:' ios/DoseTap/Views/MorningCheckInDoseAndFunctioningSections.swift \
  || fail "dose/functioning check-in UI is not owned by its bounded component"

rg -q '^    public func recordSymptomEvent\(' ios/DoseTap/Storage/EventStorage+SymptomEvents.swift \
  || fail "normalized symptom persistence is missing from EventStorage+SymptomEvents.swift"
! rg -q 'recordSymptomEvent\(' ios/DoseTap/Storage/EventStorage+CheckInSubmissions.swift \
  || fail "symptom persistence leaked back into check-in submission storage"

rg -q '^    public var currentContext:' ios/DoseTap/Storage/SessionRepositoryPresentation.swift \
  || fail "repository presentation context is missing from its extension"
! rg -q '^    public var currentContext:' ios/DoseTap/Storage/SessionRepository.swift \
  || fail "repository presentation context leaked back into the lifecycle file"

for project_source in \
  SettingsStudioExport.swift \
  SessionRepositoryPresentation.swift \
  SessionRepositoryDoseEventMetadata.swift \
  MorningCheckInDoseAndFunctioningSections.swift \
  MorningCheckInClinicalSections.swift \
  'EventStorage+SymptomEvents.swift'; do
  grep -q "$project_source" ios/DoseTap.xcodeproj/project.pbxproj \
    || fail "Xcode project is missing extracted source: $project_source"
done

printf 'Architecture boundary contract passed: responsibility splits are present and DoseCore owns the only TimeIntervalMath implementation.\n'
