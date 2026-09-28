# Local bottle tracking — DOSETAP-77

Phone candidate: **0.4.19 (82)**. Separate iPad Dashboard remains **0.1.0 (9)**.
This record describes the first bounded bottle-tracking delivery; it does not close
quantity, owner, accessibility, privacy, notification or release acceptance.

## Delivered behavior

- Tonight has a compact **Bottle & supply** entry. Management is also available
  from Settings → Supply & order reminder → Bottles & supply and the existing
  pre-sleep bottle action once tracked receipts exist.
- Record bottles actually received, defaulting to three with an editable count,
  and explicitly start a bottle from an available receipt. Receiving never opens
  a bottle or records medication. An older unlinked opening stays unlinked.
- Show current opening, ordinal within its receipt, tracked unopened bottles and
  **recorded dosing nights since opening**. A new start replaces the displayed
  opening without claiming the prior bottle was empty.
- Distinct stored treatment dates count once, including overnight doses across
  midnight. Canonical taken nighttime events count; independent daytime medicines,
  skips and snoozes do not. Conflicting date/session identities in either direction
  and duplicate canonical Dose 1/2 rows are excluded with a review count.
- Counts are read from dose history each time. Correction/undo changes the count;
  no second mutable consumption counter exists. Read errors show unavailable.
- On the last tracked bottle, show an in-app contact-planning notice. At the third
  recorded dosing night, emphasize contacting the pharmacy about the next supply.
  Validated last-bottle stock still warns if usage cannot be read. A later receipt
  clears that notice. Calendar order notifications remain an independent setting.
- Undo the latest opening or an unused receipt with confirmation. Corrections
  remain in source history. Dose records and medication alarms are unaffected.

## Data and export

The existing SQLite `supply_state` document remains the source through
SessionRepository. The first tracking write upgrades the validated payload from
version 1 to 2. Older version-1 readers reject this newer payload instead of
silently erasing receipts or corrections; do not use an older app to edit it.

Settings supply JSON, Studio ZIP/local snapshot, and Excel retain receipts,
opening links, original and recorded dates, voids and reminder revisions. The
sortable **Bottle & Supply** sheet is separate from manual **Inventory** snapshots.
`Source Fields` retains complete evidence. Exact inner dates use
`supplyStateJSON` / `json-date-seconds-since-2001-v1`; the outer bundle timestamp
format is unchanged. Malformed supply blocks publication with a named read error.
The existing nearby report includes the raw supply document; a dedicated iPad
bottle presentation is not part of this phone slice.

## Validation and integration

Core receipt/opening tests were written before implementation. Independent review
identified and corrected forward/reverse identity conflicts, last-bottle notice
loss during a failed history read, and stale Settings copy. Native review also
reduced the Tonight card's height.

- Full combined Swift suite: 859 DoseCore XCTest, 20 nearby XCTest and 43 Swift
  Testing cases passed. Build passed.
- Export suite: six native iOS integration tests passed. Extracted synthetic ZIPs
  preserve identical source supply JSON and fractional seconds; workbook receipt
  IDs, links, count and sortable rows agree with source. No private owner export
  was added to Git.
- Final native integration suite: 22 tests passed (10 storage, six service and
  six export). Reopen, write failure/retry, identity conflicts in both directions,
  third-night notices and later receipts are covered.
- Normal native receipt/start/relaunch/last-bottle/undo journey and existing
  pre-sleep bottle regression passed. Largest text and compact-layout rechecks
  remain pending. Earlier runs encountered simulator accessibility startup
  failures; only the test simulator was restarted, without erasing its data.
- Signed phone build 82 passed. Installation, hosted CI and integration evidence
  are pending in this candidate record and must be updated before closeout.

## Remaining scope and owner check

**Doses remaining is explicitly unavailable.** It requires confirmed bottle
quantity, actual consumption, preparation versus administration handling,
corrections and split-bottle use. Elapsed nights and planned amounts cannot supply
those facts. The next slice must settle these inputs before estimating stock.

The third-night notice is currently in-app, not an automatic third-night iOS
notification or a pharmacy order. A saved calendar notification remains available.
The owner must confirm whether the desired threshold is the third recorded dosing
night or a calendar-day threshold, plus the preferred daytime contact time.

After installation, use only real receipt/opening information: review Tonight →
Bottle & supply, record currently unopened bottles, confirm the actual opening,
reopen the app and compare stock/night labels. Verify later real dose logs update
the count and exports retain the records. Do not create medication logs merely to
test this. VoiceOver, physical delivery/notification behavior, privacy and release
acceptance remain open. DOSETAP-77 stays In Progress.
