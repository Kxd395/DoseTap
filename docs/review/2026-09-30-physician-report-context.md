# Physician report context and coverage checkpoint

Status: local implementation evidence; report source-adapter integration, interactive preparation, physical-device and owner acceptance remain open. Parent owns Plane closeout and release.

The immutable report now carries validated descriptive contexts and optional readable comparison labels. Raw-only evidence stays available in JSON/detail CSV and source inspection while staying out of metric denominators. Serious and unplaced records remain in the printable appendix. Calendar coverage enumerates every intersecting month, including empty months, without inventing eligible episodes or zero metric values.

Partial values remain excluded by default. An explicit include-partial choice is frozen into the snapshot; finite dated partial contributions are counted separately from complete available observations. Unknown-time or missing-value partial rows never contribute. The summary CSV preserves the same metric denominators, policy, descriptive contexts and independent calendar coverage.

Validation on this worktree:

- Initial context compile RED and subsequent policy/label compile RED reproduced the missing APIs.
- Seven focused context/policy tests passed, including the empty December month, DST/exclusive midnight, unplaced rows, source detail preservation, JSON/CSV, partial eligibility and readable labels.
- Full core suite passed: 964 XCTest and 43 Swift Testing tests.
- Five native simulator tests passed: paginated PDF plus four persistence/revision/failure tests, on simulator 21E15B3C-E6DD-4107-82B3-3AFF80BEB65C.
- The updated seven-page synthetic PDF was rendered and visually inspected at the first and last page. December's 13 days and 0 source rows remain visible; final question, source provenance and footer remain legible without clipping.
- Plane workflow guard passed 15 tests and 80 assertions. SSOT, architecture, documentation, whitespace and app-version guards passed. Version remains 0.4.19 (88).

Evidence: `.build/physician-evidence/context-policy-red.log`, `context-policy-focused.log`, `context-full-core.log`, `context-native-tests.log`, `context-native-tests.xcresult`, and `context-pdf-attachments/`. This evidence does not establish interactive source-preparation or signed-device acceptance.
