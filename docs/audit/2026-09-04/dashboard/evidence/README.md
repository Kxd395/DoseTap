# Simulator evidence

All screenshots contain display-only synthetic fixtures, not user medication/health records. Captured in iPhone 17 / iOS 26.5 simulator from app 0.4.15 (17). They demonstrate representative layout, navigation, selected-source chart data, zero-percent weekday, recent rows, empty/error and accessibility-size presentation. They do not certify every card, a physical phone, VoiceOver, or live provider parity.

- `overview.png`, `trends-whoop.png`, `weekday.png`, `recent-nights.png`, `empty-error.png`, `large-text.png`: XCTest attachments from `Test-DoseTapUITests-2026.09.05_00-25-14--0400.xcresult`.
- `landscape-large-text.png`: XCUIScreen capture from `Test-DoseTapUITests-2026.09.05_00-29-34--0400.xcresult`. Application-only screenshots during rotation had incorrect crops; full-screen capture resolved that evidence issue.
- `unit-results.json`: final 24-test XCTest result summary after provider missingness correction, `Test-DoseTap-2026.09.05_00-36-43--0400.xcresult`.
- Later provider-presence handling and small wording refinements compile and pass targeted tests; screenshots are layout evidence, not a byte-identical release-artifact certificate.


## 0.4.16 (18) full-dashboard restoration
- `restored-all.png`, `restored-inventory.png`, `restored-sparse.png`, `restored-empty.png`: display-only fixtures from the passing full-scroll/prerequisite/empty-state test, `Test-DoseTapUITests-2026.09.05_08-43-01--0400.xcresult` (1 passed).
- `restored-landscape.png`: passing large-text/rotation test in `Test-DoseTapUITests-2026.09.05_08-41-03--0400.xcresult`. Section/source/empty/error test also passed in that bundle; its full-scroll test initially failed on XCTest's long-string query limit, then passed in the later bundle above after changing to a predicate query.
- Inspected restored card content, sparse/empty explanations and full-screen landscape navigation. Screen-image aspect-ratio wait prevents capturing before rotation completes. All-card maximum-text/VoiceOver/iPad/device/provider acceptance remains open.


## Build-14 parity correction — 0.4.17 (19)
- `build14-{overview,trends,data,whoop,lifestyle,interval}.png`: final passing individual-section test in `Test-DoseTapUITests-2026.09.05_09-22-40--0400.xcresult`. Synthetic fixtures only. Restored summaries, category colors/key, readable current/prior badges, explicit missing values, one-sided lifestyle comparisons, per-night coverage and corrected gauge label are visible.
- Earlier complete regression bundle `Test-DoseTapUITests-2026.09.05_09-18-08--0400.xcresult`: 3 passed (All normal/sparse/empty; build-14 individual sections; source/weekday/error). Large-text/landscape passed separately in `Test-DoseTapUITests-2026.09.05_09-15-03--0400.xcresult`.
- These are source-backed fixture screenshots from the new app, not screenshots recovered from the owner's build-14 phone. Historical comparison uses Git sources at `433ef43` and `2b93aa0`. A transient blank morning attachment was excluded; morning fields were inspected in the lifestyle/adjacent-card capture. Full VoiceOver/iPad/all-card maximum-text/live-provider/device acceptance remains open.
