# Certificate pinning operational runbook

Status: Current runbook with an inactive shipping network surface
Last verified: 2026-09-02

## Current boundary

`ios/Core/CertificatePinning.swift` implements SHA-256 Subject Public Key Info pinning for `api.dosetap.com` and `auth.dosetap.com`. `PinnedURLSessionTransport` can apply that delegate to an approved API client.

No production call site currently initializes `APIClient`, so this implementation is not evidence of an active off-device data flow. See `docs/architecture/07-api-and-networking.md`.

Pin values are release configuration, not documentation. Do not copy active values into this file, a ticket, logs, or source. The supported configuration sources are:

- `DOSETAP_CERT_PINS` in the release environment;
- the final `DOSETAP_CERT_PINS` Info.plist value injected by Xcode build settings.

`tools/validate_release_pins.sh` requires at least two unique, well-formed pins for a Release gate.

## Important failure distinction

The runtime delegate performs default system trust evaluation when no pins are configured. It fails closed on a mismatch only when a valid pin set is present. The repository release process is therefore responsible for blocking a Release candidate with missing pins.

Do not describe the runtime as fail-closed for missing configuration. A future active production API must either make missing pins a runtime construction error or retain and prove an equivalent release-time control.

## Inspect the current certificate chain

Run from the repository root:

```bash
bash tools/rotate_cert_pins.sh api.dosetap.com
```

Review the actual leaf and intermediate chain with the service owner. A successful extraction does not approve a rotation and does not prove that a second independent backup pin is safe.

## Zero-downtime rotation

1. Obtain and independently verify the new certificate or public key.
2. Build a reviewed overlap set containing the currently accepted pin and the new pin.
3. Validate the exact Release configuration:

   ```bash
   CONFIGURATION=Release bash tools/validate_release_pins.sh
   ```

4. Ship the overlap set before the server changes.
5. Observe adoption and connection errors through approved privacy-safe telemetry.
6. Change the server certificate.
7. Remove the old pin only after the supported installed population can use the new chain.

Never replace both pins in one server-first operation. Never use a placeholder or duplicate value merely to satisfy the count check.

## Required tests

```bash
swift test --filter CertificatePinningTests
bash tools/test_validate_release_pins.sh
```

For an active endpoint, also validate on an archive-equivalent build:

- correct overlap set accepts the reviewed chain;
- wrong pin rejects the connection;
- expired or untrusted certificate fails system trust evaluation;
- a host outside the pin domain set follows its separately approved policy;
- missing configuration blocks release before distribution;
- logs contain no pin values, tokens, request bodies, or health data.

## Release gate

Use `bash tools/release_preflight.sh <tag>` with the approved release environment. The untagged form warns when pins are absent; a warning is not release approval.
