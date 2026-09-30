#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mode="${1:?Usage: run_ci_iphone_tests.sh safety|exports output-directory}"
output="${2:?An output directory is required}"
case "$mode" in
  safety)
    scheme=DoseTapUITests
    tests=(
      DoseTapUITests/DoseTapUITests/testDose1ReviewNoAlarm
      DoseTapUITests/DoseTapUITests/testDose2ConfirmationCancelBackgroundAndExplicitSave
      DoseTapUITests/DoseTapUITests/testQuickLogAvailabilityBeforeDose1
      DoseTapUITests/DoseTapUITests/testQuickLogAvailabilityBeforeDose2
    ) ;;
  exports)
    scheme=DoseTap
    tests=(
      DoseTapTests/ExportIntegrityTests/test_studioExport_preservesCheckInPayloadsAndInventoryRows
      DoseTapTests/ExportRecordFidelityTests/testConflictingSessionsExportAllSourcesWithoutCombinedSummariesOrRecordChanges
      DoseTapTests/ExportRecordFidelityTests/testMedicationOnlySessionReachesActualArchiveWithStoredFields
      DoseTapTests/ExportRecordFidelityTests/testEventIdentityAndProvenanceReachEveryArchiveRepresentation
      DoseTapTests/WHOOPExportStatusTests/testPartialRecoveryPreservesSleepAndFetchEvidenceInProductionArchive
      DoseTapTests/AppleHealthExportMissingnessTests/testBiometricOnlyEvidenceReachesProductionArchiveWithoutSleepClaims
    ) ;;
  *) echo "Unsupported test mode: $mode" >&2; exit 2 ;;
esac
mkdir -p "$output"
output="$(cd "$output" && pwd)"
if [[ -e "$output/tests.xcresult" ]]; then
  echo 'Refusing to overwrite an existing result bundle.' >&2; exit 1
fi
if [[ ! -f ios/DoseTap/Secrets.swift ]]; then
  cp ios/DoseTap/Secrets.template.swift ios/DoseTap/Secrets.swift
fi
if [[ -z "${DT_TEST_DESTINATION:-}" ]]; then
  xcrun simctl list devices available --json > "$output/devices.json"
  simulator="$(python3 - "$output/devices.json" <<'PYTHON'
import json, re, sys
with open(sys.argv[1]) as stream:
    devices = json.load(stream)['devices']
preferred = ['iPhone 17 Pro', 'iPhone 16 Pro', 'iPhone 15 Pro', 'iPhone 14 Pro']
candidates = [(tuple(map(int, re.findall(r'\d+', runtime))), len(preferred) - preferred.index(device['name']) if device['name'] in preferred else 0, device['udid'])
              for runtime, values in devices.items() if 'iOS' in runtime
              for device in values if device.get('isAvailable') and device['name'].startswith('iPhone')]
if not candidates:
    raise SystemExit('No available iPhone simulator')
print(max(candidates)[2])
PYTHON
  )"
  xcrun simctl bootstatus "$simulator" -b
  export DT_TEST_DESTINATION="platform=iOS Simulator,id=$simulator"
fi
args=()
for test in "${tests[@]}"; do args+=("-only-testing:$test"); done
DT_SCHEME="$scheme" tools/dt-test all "${args[@]}" \
  -derivedDataPath "$output/DerivedData" -resultBundlePath "$output/tests.xcresult" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" 2>&1 | tee "$output/tests.log"
for test in "${tests[@]}"; do
  method="${test##*/}"
  if ! grep -Eq "Test [Cc]ase .*${method}.* passed" "$output/tests.log"; then
    echo "Required test did not pass: $test" >&2; exit 1
  fi
done
echo "All required $mode tests executed and passed."
