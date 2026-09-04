# 07 — API and Networking

Status: Current architecture reference
Last verified: 2026-09-02

## Shipping boundary

DoseTap is local-first. Medication state is not sent through `APIClient`, and the client has no take, skip, or snooze endpoint. Every medication action must use the local `DoseActionCoordinator` → `SessionRepository` → `EventStorage` path described in `12-safety-sensitive-legacy-retirement.md`.

No production call site currently initializes `APIClient`. Its remaining surface is retained for explicit future integration work and is not evidence that an off-device service is active.

## APIClient

File: `ios/Core/APIClient.swift`

`APIClient` is an async HTTP client with an injected transport. Its endpoint enum contains only:

```swift
public enum Endpoint: String, CaseIterable {
    case logEvent = "/events/log"
    case exportAnalytics = "/analytics/export"
}
```

The methods are:

- `logEvent(_:at:)` — POST an explicitly supplied non-medication event.
- `exportAnalytics()` — GET an explicitly requested analytics payload.

Both methods map HTTP failures through `APIError`. Neither method is wired into the shipping app runtime.

## Transport and pinning

`APITransport` provides the injected send boundary. `URLSessionTransport` is the ordinary implementation and test suites use stubs. `PinnedURLSessionTransport` and `CertificatePinning` provide the Release TLS trust policy for any approved future production call site.

Certificate pins are SHA-256 SPKI pins injected into the final Release `Info.plist`. Release packaging fails when the required pins are absent or malformed. Pinning does not authorize a new data flow; privacy, consent, offline behavior, and endpoint semantics still require their own approved integration.

## Offline queue

`OfflineQueue.swift` remains a generic tested utility, but no shipping medication action uses it. The former `DosingService` action façade was removed because replaying medication mutations outside the local policy and transaction context is unsafe.

Any future queue must define payload classification, retention, redaction, idempotency, replay conflicts, cancellation, and user-visible failure. Medication actions require a new architecture decision and may not be added as generic queued requests.

## Contract guard

`tools/check_legacy_safety_paths.sh` rejects remote medication endpoint strings and retired mutation façades in shipping source. `APIContractTests` asserts that the client and OpenAPI placeholder expose the same two non-medication paths.

## Errors

`APIErrors.swift` retains transport and server error decoding used by API tests and possible future non-medication integrations. Some historical medication-domain error cases remain data types only; they do not create a request path.
