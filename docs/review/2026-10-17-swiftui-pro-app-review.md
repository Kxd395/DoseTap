# SwiftUI Pro application review

Status: Source review recorded; application fixes and live UI acceptance are not performed. Plane registration is blocked.
Date: 2026-10-17
Reviewed source: `0150bf05e757b1943d166a37e626d42fc11974d9`, `feat/sleep-chart-inspection`.

## Wiring and scope

The active checkout contains the pinned SwiftUI Pro skill and AGENTS.md explicitly requires it for relevant SwiftUI work. All 17 source-file hashes and referenced documents were checked again. This review loaded the skill and its applicable accessibility, view, data-flow, performance and layout guidance.

The preserved `/Volumes/Developer/projects/DoseTap` checkout and `DoseTap-main` do not contain this skill. The current thread's injected skill catalog does not list it either. Explicit loading from the active checkout works; automatic discovery in a fresh client session has not been demonstrated. Integration into another branch/worktree remains a separate operation.

Review concentrated on the daytime editor, morning questionnaire, bedtime questionnaire, shared controls and dashboard refresh/inspection paths. This is a bounded source review, not an exhaustive app, security, clinical or physical-device audit. Upstream recommendations are subordinate to DoseTap's existing targets, contracts and architecture. No SwiftUI/API migration is proposed merely to satisfy the skill.

## Findings

### SUI-01 — P2: Shared questionnaire choices omit selected-state accessibility

Locations: `ios/DoseTap/Views/PreSleepLogComponents.swift:39` (`OptionGrid`), `:77` (`MultiSelectGrid`), `:105` (`StressSlider`); `ios/DoseTap/Views/MorningCheckInSections.swift:170` (`MorningCheckInGrogginessPicker`).

The custom buttons change color, weight or background when selected, but expose no selected trait or selection value. These controls are used across both morning and bedtime questionnaires. Selection cannot be inferred by assistive technology from those visual styles. Exact spoken output still needs a VoiceOver check.

Reproduction: open either questionnaire, focus a choice, activate it, then move away and return with VoiceOver. Check whether the selected answer is distinguishable from other answers. Repeat with a multi-select choice selected and then deselected.

Required fix: add the corresponding selection predicate as an accessibility trait and a visible non-color selected indicator. Keep the stored answers and existing tap semantics unchanged. The daytime rating buttons already provide the trait at `DaytimeCheckInView.swift:188`.

Before, on an `OptionGrid` button:

```swift
.buttonStyle(.plain)
```

After:

```swift
.buttonStyle(.plain)
.accessibilityAddTraits(selection == option ? .isSelected : [])
```

Use `selections.contains(option)`, `value == level`, and `viewModel.grogginess == level` for the other three controls. A decorative checkmark can reinforce selection visually without changing the option's accessible name.

Validation: assert selected/unselected accessibility state after single-select changes and multi-select toggles; check VoiceOver plus largest Dynamic Type. Verify identical persisted answers before and after this presentation change.

### SUI-02 — P2: Two morning sliders have no explicit question label

Locations: `ios/DoseTap/Views/MorningCheckInSections.swift:237`; callers at `ios/DoseTap/Views/MorningCheckInClinicalSections.swift:120` and `:128`.

`MorningCheckInScoreSlider` constructs an unlabeled `Slider`. Its surrounding sibling text contains endpoint descriptions and a numeric score, but the slider has no accessible question label. The two uses represent different concepts: self-reported driving confidence and daytime sleepiness. Their numeric values alone do not identify the question.

Reproduction: enable the optional work/safety section and move between its two sliders with VoiceOver. Check whether each announces the question and the 1–5 value without requiring navigation to neighboring text.

Required fix: add a `LocalizedStringKey` question label to the reusable component, show the label, and supply it to the slider's accessibility label; give the current score as “N out of 5.” At the two call sites use the existing concepts “Driving confidence” and “Daytime sleepiness.” Preserve the ranges, increments and self-report meaning; this must not imply driving clearance.

Before, after the slider initializer:

```swift
.tint(accentColor)
```

After, with `let questionLabel: LocalizedStringKey` added to the component:

```swift
.tint(accentColor)
.accessibilityLabel(Text(questionLabel))
.accessibilityValue(Text("\(value) out of \(range.upperBound)"))
```

Validation: verify distinct slider names and correct values through each range, including VoiceOver adjustment. Do not change questionnaire persistence or interpretation.

### SUI-03 — P2: Bedtime paging requests animation regardless of Reduce Motion

Locations: `ios/DoseTap/Views/PreSleepLogView.swift:112`, `:119`, `:138`; existing policy at `ios/DoseTap/UserSettingsManager.swift:111`.

The page animation and Next/Back actions request animations unconditionally. They do not consult either the app's reduced-motion preference or the system setting. DoseTap already exposes a combined `shouldReduceMotion` policy and a synchronous `withAccessibleAnimation` helper, but this flow does not use them. This establishes the missing policy check in source; actual page motion has not been observed in this review.

Reproduction: enable the app's Reduced Motion setting while system Reduce Motion is off, then use Next/Back in the bedtime questionnaire. Repeat with the system setting enabled. Compare against normal motion.

Required fix: observe the app preference and system environment, use a nil animation when either requests reduced motion, and guard explicit Next/Back animations too. Keep the same view hierarchy so changing the preference cannot discard entered answers. Do not simply replace the modifier with the current `ConditionalAnimationModifier`: its conditional branches should first be made structurally stable if reused.

Before:

```swift
.animation(.easeInOut(duration: 0.3), value: currentCard)
```

After, with `reduceMotion` computed from observed app and system preferences:

```swift
.animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentCard)
```

Validation: exercise both preference sources, Next/Back and setup-driven page changes; ensure all answers survive navigation and preference changes. Obtain simulator motion proof and keep phone comfort/usability acceptance separate.

## Usability proposal: Keep morning completion within reach

`MorningCheckInView.swift:78` places the only submit section after all questionnaire sections. Its toolbar at `:91` provides Close/Cancel, but no submit action. A person answering only the initial questions must still scroll to the bottom to save.

Recommended next slice: move the existing submission section to a safe-area inset, or expose an equivalent toolbar action through one shared submission coordinator. Preserve validation, submission disabling, error presentation, history review and the saved-but-reminder-warning flow in `MorningCheckInSections.swift:70`. Do not turn closing the sheet into saving, duplicate the submission implementation, or change unanswered-value semantics.

This is a source-supported usability opportunity, not a measured completion-time claim. Validate short and expanded forms, keyboard visibility, largest text, failed storage writes, reminder warnings and history review. The daytime editor already offers a top Save action and collapsed optional details; retain that approach.

## Dashboard assessment and priorities

The inspected chart taps need coordinates, so replacing them with ordinary buttons would remove intended interaction. Dashboard refresh already cancels older tasks and checks generation, provider access and local revision before publishing. The work-report projections also yield and coalesce publications. These are reasons not to apply generic skill rules mechanically.

No confirmed dashboard speed regression was established by this review. Profile representative record volumes before claiming that view extraction, Observation migration or removing a binding improves performance. Broader file-size/style changes are not acceptance failures.

Priority: SUI-01 and SUI-02 first, then the reachable morning completion action, then SUI-03. Investigate cramped largest-text layouts with actual rendering before reporting clipping as a confirmed defect.

## References and open gates

- [Apple accessibility modifiers](https://developer.apple.com/documentation/SwiftUI/View-Accessibility) describes explicit labels and values alongside SwiftUI's automatic support.
- [Apple Reduce Motion guidance](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion) requires avoiding large animations when the setting is enabled.
- [Skill integration record](2026-10-17-swiftui-agent-skill.md) records provenance and packaging validation.

The live Plane equivalent-item search again failed with connection refused at `plane.localhost:3301`. No work item or tracker update is claimed. Register or match the exact review/remediation item when available, preflight it before application implementation, and independently verify its eventual closeout.

This report changes no application code. Simulator behavior, spoken VoiceOver output, physical-device usability and the proposed fixes remain unverified and unapplied.

Repository validation for this documentation change passed: `swift test -q` (1,203 XCTest and 43 Swift Testing cases), `bash tools/check_plane_workflow.sh` (15 tests, 80 assertions), `bash tools/doc_lint.sh`, local report-link checks and `git diff --check`. These checks do not establish the proposed UI fixes or close the live Plane gate.
