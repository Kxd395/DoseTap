# Simulator evidence

All screenshots contain display-only synthetic fixtures, not user medication/health records. Captured in iPhone 17 / iOS 26.5 simulator from app 0.4.15 (17). They demonstrate representative layout, navigation, selected-source chart data, zero-percent weekday, recent rows, empty/error and accessibility-size presentation. They do not certify every card, a physical phone, VoiceOver, or live provider parity.

- `overview.png`, `trends-whoop.png`, `weekday.png`, `recent-nights.png`, `empty-error.png`, `large-text.png`: XCTest attachments from `Test-DoseTapUITests-2026.09.05_00-25-14--0400.xcresult`.
- `landscape-large-text.png`: XCUIScreen capture from `Test-DoseTapUITests-2026.09.05_00-29-34--0400.xcresult`. Application-only screenshots during rotation had incorrect crops; full-screen capture resolved that evidence issue.
- `unit-results.json`: final 24-test XCTest result summary after provider missingness correction, `Test-DoseTap-2026.09.05_00-36-43--0400.xcresult`.
- Later provider-presence handling and small wording refinements compile and pass targeted tests; screenshots are layout evidence, not a byte-identical release-artifact certificate.
