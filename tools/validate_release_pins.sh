#!/usr/bin/env bash
set -euo pipefail

if [[ "${CONFIGURATION:-Release}" != "Release" ]]; then
  echo "Skipping pin validation for non-Release configuration: ${CONFIGURATION:-unknown}"
  exit 0
fi

PINS="${DOSETAP_CERT_PINS:-}"

if [[ -z "$PINS" ]]; then
  echo "ERROR: DOSETAP_CERT_PINS is required for Release builds."
  exit 1
fi

IFS=',' read -r -a RAW_PINS <<< "$PINS"
UNIQUE_PINS=()

for pin in "${RAW_PINS[@]}"; do
  trimmed="$(echo "$pin" | xargs)"
  [[ -z "$trimmed" ]] && continue

  if [[ "$trimmed" == *"REPLACE"* ]] || [[ "$trimmed" == *"TODO"* ]] || [[ "$trimmed" == *"example"* ]]; then
    echo "ERROR: Placeholder pin detected: $trimmed"
    exit 1
  fi

  # SHA-256 SPKI pins must be exactly 32 bytes of digest in base64 form (43 chars + '=' padding).
  if [[ ! "$trimmed" =~ ^sha256/[A-Za-z0-9+/]{43}=$ ]]; then
    echo "ERROR: Invalid SPKI pin format: $trimmed"
    echo "Expected format: sha256/<44-char-base64-digest>"
    exit 1
  fi

  duplicate=false
  if (( ${#UNIQUE_PINS[@]} > 0 )); then
    for existing in "${UNIQUE_PINS[@]}"; do
      if [[ "$existing" == "$trimmed" ]]; then
        duplicate=true
        break
      fi
    done
  fi

  if [[ "$duplicate" == false ]]; then
    UNIQUE_PINS+=("$trimmed")
  fi
done

VALID_COUNT=${#UNIQUE_PINS[@]}

if [[ "$VALID_COUNT" -lt 2 ]]; then
  echo "ERROR: At least 2 unique valid pins are required for safe rotation. Found: $VALID_COUNT"
  exit 1
fi

echo "Release pin validation passed with $VALID_COUNT unique pin(s)."
