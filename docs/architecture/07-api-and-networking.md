# 07 — API & Networking

## APIClient

File: `ios/Core/APIClient.swift` (179 lines)

Platform-free async/await HTTP client in DoseCore.

### Transport Protocol

```swift
public protocol APITransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// Production: URLSessionTransport
// Tests: StubTransport (returns canned responses)
```

### Endpoints

```swift
public enum Endpoint: String, CaseIterable {
    case takeDose        = "/doses/take"
    case skipDose        = "/doses/skip"
    case snoozeDose      = "/doses/snooze"
    case logEvent        = "/events/log"
    case exportAnalytics = "/analytics/export"
}
```

### Response Models

```swift
struct DoseResponse: Codable {
    let eventId: String      // "event_id"
    let type: String
    let at: String           // ISO8601
    let dose2Window: WindowResponse?
}

struct WindowResponse: Codable {
    let min: String          // ISO8601 earliest
    let max: String          // ISO8601 latest
}

struct SnoozeResponse: Codable {
    let eventId: String
    let minutes: Int
    let newTargetAt: String
}

struct SkipResponse: Codable {
    let eventId: String
    let reason: String?
}

struct EventResponse: Codable {
    let eventId: String
    let event: String
    let at: String
}
```

### Request Construction

```swift
func makeRequest(path:method:body:) throws -> URLRequest
// Sets: Content-Type: application/json
// Sets: Authorization: Bearer <token>
// Encodes body as JSON
```

---

## APIErrors

File: `ios/Core/APIErrors.swift`

### Error Types

```swift
public enum APIError: Error, Equatable {
    case invalidResponse
    case httpError(Int)
    case decodingError
    case networkError(String)
}

public enum DoseAPIError: Error, Equatable {
    case windowExceeded          // 422_WINDOW_EXCEEDED
    case snoozeLimit             // 422_SNOOZE_LIMIT
    case dose1Required           // 422_DOSE1_REQUIRED
    case alreadyTaken            // 409_ALREADY_TAKEN
    case rateLimit               // 429_RATE_LIMIT
    case deviceNotRegistered     // 401_DEVICE_NOT_REGISTERED
    case unknown(Int, String)    // Unmapped error
}
```

### Error Mapper

```swift
struct APIErrorMapper {
    static func map(data: Data, status: Int) -> Error
    // Decodes APIErrorPayload { code, message }
    // Maps to DoseAPIError based on code string
}

struct APIErrorPayload: Codable {
    let code: String
    let message: String
}
```

---

## OfflineQueue

File: `ios/Core/OfflineQueue.swift`

Actor-based retry queue for failed API calls.

```swift
public actor OfflineQueue {
    func enqueue(_ action: DosingService.Action) async
    func flushPending() async
    func pendingCount() -> Int
    func clear() async
}
```

### Behavior

```text
API call fails (network/timeout)
  │
  ▼
DosingService catches error
  │
  ▼
OfflineQueue.enqueue(action)
  │
  ▼
On next app foreground or connectivity:
  │
  ▼
OfflineQueue.flushPending()
  ├── Retry each queued action
  ├── Remove on success
  └── Keep on failure (retry next time)
```

---

## DosingService (Façade)

File: `ios/Core/APIClientQueueIntegration.swift`

Actor combining APIClient + OfflineQueue + EventRateLimiter.

```swift
public actor DosingService {
    public enum Action: Codable, Sendable, Equatable {
        case takeDose(type: String, at: Date)
        case skipDose(sequence: Int, reason: String?)
        case snooze(minutes: Int)
        case logEvent(name: String, at: Date)
    }

    func perform(_ action: Action) async throws
    // Routes to APIClient method
    // On failure: enqueues in OfflineQueue
    // Respects EventRateLimiter

    func flushPending() async
    // Retries offline queue
}
```

---

## EventRateLimiter

File: `ios/Core/EventRateLimiter.swift`

Actor-based debounce for repeated events.

```swift
public actor EventRateLimiter {
    func shouldAllow(_ event: String) async -> Bool
    func recordEvent(_ event: String) async

    // Default cooldowns:
    // "bathroom": 60 seconds
}
```

---

## CertificatePinning

File: `ios/Core/CertificatePinning.swift` (251 lines)

TLS certificate pinning for API calls.

```swift
public final class CertificatePinning: NSObject, URLSessionDelegate {
    init(pins: [String], domains: [String], allowFallback: Bool)

    // Pins: SHA-256 of SPKI (Subject Public Key Info)
    // Domains: ["api.dosetap.com", "auth.dosetap.com"]
    // Fallback: false in production, configurable in DEBUG

    static func forDoseTapAPI() -> CertificatePinning
    static var hasConfiguredPins: Bool
}
```

Pin sources (priority order):

1. Environment variable `DOSETAP_CERT_PINS`
2. Info.plist key `DOSETAP_CERT_PINS`

---

## CSVExporter

File: `ios/Core/CSVExporter.swift`

Exports session data to CSV format for sharing.

```swift
public struct CSVExporter {
    static func export(sessions: [ExportableSession]) -> String
}
```
