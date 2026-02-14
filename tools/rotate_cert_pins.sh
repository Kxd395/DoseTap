#!/usr/bin/env bash
# rotate_cert_pins.sh — Generate SPKI SHA-256 pin for DoseTap API server
#
# Usage:
#   bash tools/rotate_cert_pins.sh api.dosetap.com
#
# Output: base64-encoded SHA-256 of the server's SPKI (Subject Public Key Info)
# Set this in your environment or Info.plist as DOSETAP_CERT_PINS.
#
# Rotation Procedure:
#   1. Run this script against the new certificate BEFORE deploying it.
#   2. Add the NEW pin alongside the OLD pin (comma-separated) in DOSETAP_CERT_PINS.
#   3. Ship the app update with both pins.
#   4. Deploy the new server certificate.
#   5. After all users have updated, remove the old pin in a subsequent release.
#
# Example DOSETAP_CERT_PINS value (2 pins for overlap):
#   "sha256/OLD_PIN_BASE64=,sha256/NEW_PIN_BASE64="
#
# Keep at least 2 pins active during rotation to avoid lockouts.

set -euo pipefail

DOMAIN="${1:-api.dosetap.com}"
PORT="${2:-443}"

echo "Fetching certificate from ${DOMAIN}:${PORT}..."

# Extract the leaf certificate's public key and hash it
HASH=$(
  openssl s_client -connect "${DOMAIN}:${PORT}" -servername "${DOMAIN}" </dev/null 2>/dev/null \
    | openssl x509 -pubkey -noout 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | openssl dgst -sha256 -binary \
    | base64
)

if [ -z "${HASH}" ]; then
  echo "❌ Failed to extract pin from ${DOMAIN}:${PORT}"
  echo "   Make sure the domain is reachable and has a valid TLS certificate."
  exit 1
fi

PIN="sha256/${HASH}"

echo ""
echo "✅ SPKI SHA-256 pin for ${DOMAIN}:"
echo "   ${PIN}"
echo ""
echo "Set in environment:"
echo "   export DOSETAP_CERT_PINS=\"${PIN}\""
echo ""
echo "Or in Info.plist:"
echo "   <key>DOSETAP_CERT_PINS</key>"
echo "   <string>${PIN}</string>"
