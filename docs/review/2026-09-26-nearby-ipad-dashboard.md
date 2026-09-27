# Separate iPad dashboard and nearby reporting

Status: Device candidate; DOSETAP-76 remains In Progress.

The owner selected both a private-server investigation and a direct iPhone/iPad
connection. This slice implements the foreground nearby route. It does not enable
clinical CloudKit uploads, a private-server feed or continuous background sync.

## Apps and ownership

- Phone: DoseTap 0.4.19 (78), `com.dosetap.ios`. Existing logging, SQLite and alarms
  remain phone-owned. Settings adds **Connect iPad Dashboard**.
- iPad: DoseTap Dashboard 0.1.0 (3), `com.dosetap.dashboard`, a separate application
  generated from `ipad/project.yml`. It has no EventStorage, repository writer,
  dose action or alarm service. The existing full DoseTap installation is preserved.
- The iPad stores one validated local reporting snapshot, protected and excluded
  from backup. Forget removes that copy and source selection, not phone records.
- The iPhone retains a separate durable publisher ID and monotonic revision.
  Reservation happens before capture. Failed capture/send can consume a revision;
  it cannot reuse an already issued revision or change a clinical record.

## Owner workflow

1. On iPhone, open Settings → Connect iPad Dashboard → Start nearby reporting.
2. Open the separate DoseTap Dashboard app on iPad, then Connection → Find my iPhone.
3. Select the phone in the iPad discovery list, then accept the invitation on the
   phone. Both screens show six digits. Compare all six and tap **Codes match** on
   BOTH devices. If they differ, tap **Codes do not match** to end the attempt.
   Nothing is copied, typed or sent through Messages. Names alone are not identity.
4. After both confirmations and authentication, choose Refresh report from iPhone.
5. Compare medication occurrence/calendar dates, stored/recorded timestamps,
   treatment dates and conflict states. Reopen the iPad app to check cached review.

Keep both apps open. Local Network permission is required. Ending the connection
or backgrounding either app discards pairing state. A new connection uses a new
comparison. No clipboard or camera access is needed. Discovery does not remotely
open the phone app or start its publisher. When no phone is found, the iPad names
the full phone Settings path and Local Network permission requirement.

Owner feedback on phone 77/iPad 2: discovery remained waiting and the 64-character
key was impractical; switching to Messages ended the foreground session. Builds
78/3 replace that flow with six-digit comparison. The key exchange stays internal;
the six digits are not an encryption password. Comparison expires after two minutes;
connection/transfer waits expire after 30 seconds. Retry requires an explicit new
attempt with fresh key material. Actual paired transfer acceptance remains open.

## What is shown

The separate iPad dashboard uses dark appearance throughout, including connection,
charts, medication history and native sheets. This app-level preference does not
change the iPad system appearance or the iPhone app.

Overview offers 7/30/90/180/365 days and All Time. Six months means 180 inclusive
calendar treatment dates. Only a positive, unambiguous reported Dose 1/Dose 2 pair
contributes to spacing. The median has its own usable-pair denominator. Session
identity checks union dose_events, sleep_sessions and current_session, including
multiple IDs per date and one ID spanning dates. No historical medication-window
or effectiveness classification is invented.

Medication history is all available independent administrations, ordered by
occurrence. Saved occurrence offset supplies the calendar date; display clock
values disclose the iPad's current time zone. Unknown occurrence stays unknown.
Legacy creation time is labeled Stored creation (may be import time). Canonical
preset administration recording time remains Recorded. Amounts retain exact
Decimal values in the canonical projection.

The snapshot retains questionnaires, quick logs, symptoms, schedule, inventory and
other local source evidence. Initial views do not yet interpret every source.
Apple Health/WHOOP measurements are explicitly unavailable in this first nearby
report; it does not fabricate sleep analytics or silently call provider APIs.

## Validation and limitations

- Core snapshot/projection tests include ordering, missingness, corruption,
  midnight/DST, Decimal amounts and conflicting session evidence.
- 20 nearby tests cover codec/budget behavior plus commitment/reveal ordering,
  tampering, role reflection, duplicate messages, correctly directed old-session
  confirmation, simultaneous confirmations, and encrypted report round-trip.
  Neither one device confirmation nor peer confirmation alone releases a key.
- 9 native phone storage/revision tests passed, including concurrent SQLite snapshot
  consistency. Physical Data Protection attributes are not established by simulator
  tests; their assertion is compiled for physical-device execution only.
- 7 native iPad cache tests passed; 2 native UI journeys passed at normal and largest
  text, using clearly synthetic records. Native screenshots are xcresult evidence.
- 1 native phone UI journey checks the explicit publisher entry and unpaired state.
- The initial phone simulator runner crashed before bootstrap. Fresh DerivedData
  with debug-dylib injection disabled ran the tests; this is distinct from test
  failures. One test assertion incorrectly expected simulator file-protection
  metadata; it was constrained to physical devices and rerun successfully.
- Signed phone 78 and separate iPad 3 installed, inventory-read back and launched.
  Existing full DoseTap 76 on the iPad remains installed unchanged.
- The earlier hosted iPad largest-text job timed out while launching its app; the
  workflow now waits for simulator boot and runs tests serially. Hosted rerun is
  required; local passing journeys do not override a failed hosted check.

The six-digit comparison implementation and transition into directional authenticated
encryption were independently source-reviewed. Ephemeral X25519 keys and random
nonces are committed before reveal; domain-separated transcript/HKDF/HMAC operations
bind both roles. Human comparison provides limited per-attempt authentication;
confirming without comparing defeats that check. This is a custom protocol, not
a protocol security certification. The old 64-character workflow is superseded.
Hosted CI also found an older macOS SDK availability error for HKDF in the payload
codec; explicit macOS 11 guards now fail closed on unsupported systems.
Real paired transfer, denial/retry/reconnection, real-report parity, physical cache
protection, VoiceOver and privacy/release acceptance remain open. No owner acceptance
is inferred from unit tests, simulator results, installation or merge.

## Private-server route

The reviewed restricted `serverctl status` attempt failed with public-key
authentication denied and no gateway response. No arbitrary SSH fallback, remote
change, credential exposure or health-data upload was performed. Current database,
authentication, retention and backup readiness remain unverified. Restore the
approved restricted access path and add a fixed metadata inventory action before
selecting or implementing a server transport.

## Developer commands

XcodeGen 2.46+ and the project Apple developer CLI setup are prerequisites.

```bash
tools/dt-dashboard-build sim
tools/dt-dashboard-build device <ipad-device-id>
xcodegen generate --spec ipad/project.yml
xcodebuild test -project ipad/DoseTapDashboard.xcodeproj -scheme DoseTapDashboard \
  -destination 'platform=iOS Simulator,id=<ipad-simulator-id>' CODE_SIGNING_ALLOWED=NO
```

The generated project and plist are ignored; `ipad/project.yml` is authoritative.
The separate iPad CI workflow builds and runs cache/UI tests. Debug-only synthetic
UI fixtures are excluded from the signed Release iPad build and never read owner
records. Rolling back the separate app does not roll back or delete phone records.
