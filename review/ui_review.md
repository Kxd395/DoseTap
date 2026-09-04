This screen has useful pieces, but the current composition is overloaded, inconsistent, and visually unstable. The biggest problem is not one spacing issue. It is that the screen is trying to be **setup, active dosing, overdue check-in, quick log, morning closeout, navigation, and analytics** all at once.

From this static screenshot, the main design risk is clear: the app looks powerful, but the user cannot tell what the single next correct action is.

## Critical issues

### 1. The screen has split-state UX

The app is showing several conflicting states at the same time:

* “Incomplete Session, Complete check-in for Jun 11”
* “Tap below to start”
* “Quick 30-second check-in”
* “Take Dose 1”
* “Wake Up & End Session”
* “This Week”
* “Dose Intervals”

That is too many modes on one screen.

A user should not see  **start session** ,  **take dose** ,  **complete prior session** , and **end session** as equal visual options. That creates decision confusion and also reflects the split-brain risk you described earlier.

Fix the home screen around one active state:

```text
State 1: Prior session incomplete
Primary action: Finish Jun 11 check-in
Secondary action: Dismiss or remind later

State 2: Tonight not started
Primary action: Start tonight
Secondary: Edit wake time

State 3: Active session
Primary action: Take next dose
Secondary: Snooze, quick log, undo

State 4: Morning closeout
Primary action: Wake up and end session
Secondary: Edit wake time, add notes

State 5: Review mode
Primary action: View insights
```

Do not mix all five.

---

## Highest-priority layout correction

Current vertical order is weak:

```text
Header
Sleep Plan
Just for tonight
Incomplete Session
Start Session
Check-in
Take Dose 1
Quick Log
Wake Up & End Session
Dose/Snooze stats
This Week
Dose Intervals
```

Better order for this exact state:

```text
Header
Blocking item: Finish Jun 11 check-in
Tonight sleep plan
Primary action: Start tonight or Take Dose 1, not both
Compact quick log
Dose status strip
This week summary collapsed
```

If the prior session is incomplete, it should be the first actionable card after the header because it blocks the integrity of the current session.

---

## Header

### Problems

The header feels oversized and under-structured.

* “DoseTap” is very large relative to the available width.
* The Dark toggle competes with the app title.
* The date line is useful, but the title/date/toggle group does not feel like a clean app header.
* The Dark toggle looks like a developer setting, not something that should occupy prime dashboard space.

### Fix

Use a compact header:

```text
DoseTap                         moon icon
Tonight, Fri Jun 12
```

Specific changes:

```text
Title size: 32 to 36 pt, not huge
Date size: 17 to 19 pt
Top padding: 24 pt
Bottom padding after date: 12 pt
Remove full “Dark” pill from home screen
Move theme toggle into Settings
```

If you keep a theme control on this screen, use only an icon button. The word “Dark” is wasting space.

---

## Sleep Plan card

### What works

This is probably the strongest card on the screen. It has a clear purpose and the timing information is useful.

### Problems

* The card is too dense in the lower row.
* “Sleep if in bed now” wraps awkwardly.
* “11h 35m” is too visually loud compared with the rest of the sleep plan.
* “Wake by 7:00AM” should be “Wake by 7:00 AM”.
* The divider is okay, but the header row feels slightly cramped.
* The green “Start winding down in 3h 15m” is good, but it should not overpower every other time metric.

### Fix

Use a cleaner hierarchy:

```text
Sleep Plan                         Wake 7:00 AM
Start winding down in 3h 15m

Bedtime          Wind-down          Sleep window
10:45 PM         10:25 PM           11h 35m
```

Spacing recommendation:

```text
Card horizontal padding: 16 pt
Card vertical padding: 16 pt
Header row bottom gap: 12 pt
Divider gap: 12 pt
Metric label to value gap: 4 pt
Card corner radius: 16 pt
```

Do not let the third column wrap to 3 lines. Rename it to something shorter, like:

```text
Sleep window
11h 35m
```

or:

```text
If in bed now
11h 35m
```

---

## “Just for tonight” card

### Problems

This card is too tall for its importance.

* It uses almost the same height as a primary action card.
* The title is too large and nearly wraps.
* The text “Uses your Typical Week wake time (7:00AM)” has odd capitalization.
* The toggle is visually detached and not clearly labeled.
* Border style differs from other cards, which makes it feel like a special mode but the meaning is not obvious.

### Fix

Make it a compact settings row, not a feature card.

Better:

```text
Just for tonight                  toggle
Use typical wake time, 7:00 AM
```

Recommended size:

```text
Height: 64 to 76 pt
Padding: 16 pt
Title: 17 to 19 pt
Subtitle: 13 to 15 pt
```

Wording fix:

```text
Use typical wake time, 7:00 AM
```

Do not capitalize “Typical Week” unless it is the official name of a setting.

---

## Orange “Incomplete Session” card

### This is the biggest visual problem.

It is oversized, too saturated, and semantically confusing.

Current text reads like:

```text
Incomplete Session
Complete
Complete check-in for Jun 11
Complete
X
```

The repeated “Complete” is bad. The button label and body text collide semantically.

The orange card also overwhelms the screen. It has the visual weight of an emergency alert, but the action is a routine check-in.

### Fix

Make it a compact warning banner.

Better structure:

```text
Incomplete session
Finish Jun 11 check-in
[Finish]       [Dismiss]
```

Or:

```text
Finish previous check-in
Jun 11 is incomplete
[Finish]
```

Recommended design:

```text
Height: 76 to 92 pt
Background: dark card with orange left accent, not full orange fill
Title: 17 pt semibold
Body: 14 pt
Button: small filled orange or text button
Close button: 44 x 44 pt tap target
```

Avoid a full orange block unless the condition is urgent or dangerous.

---

## Blue “Tap below to start” card

### Problems

This card looks broken or disabled.

* There appears to be nearly invisible text above “Tap below to start”.
* The card says to tap below, but it is itself a large tappable-looking card.
* It competes with the separate “Take Dose 1” button.
* The same blue is used for multiple actions, so the primary action is unclear.

### Fix

Delete this card or merge it with the actual action.

Use one primary CTA:

```text
Start tonight
```

or:

```text
Take Dose 1
```

Not both.

Recommended button:

```text
Height: 56 pt
Full width
Corner radius: 14 to 16 pt
Text: 18 to 20 pt semibold
```

If the session has not started, show:

```text
Start tonight
```

After the session starts, replace it with:

```text
Take Dose 1
```

Do not show “Tap below to start.” It is instructional filler.

---

## Purple “Pre-Sleep Check” card

### Problems

This card has serious contrast issues.

* The title is almost invisible.
* The disabled-looking opacity makes it unclear whether the card is available.
* “Quick 30-second check-in” is useful, but the surrounding visual treatment is weak.
* The chevron suggests navigation, but the card also looks like an action button.

### Fix

Decide whether this is available.

If available:

```text
Pre-sleep check-in
Quick 30 seconds
```

If unavailable:

```text
Pre-sleep check-in
Available after session starts
```

Do not use near-invisible text. Disabled content still needs to be readable.

Recommended:

```text
Height: 64 to 72 pt
Use dark card background
Use purple icon or small accent, not full purple block
Chevron aligned center-right
```

---

## “Take Dose 1” button

### Problems

This should be the dominant action, but it is visually competing with the blue start card and the yellow end-session card.

Also, if the session has not started, “Take Dose 1” may be logically unsafe. If taking Dose 1 starts the session automatically, the button should say that.

### Fix

Choose one:

```text
Start session
```

or:

```text
Take Dose 1
```

or:

```text
Start and take Dose 1
```

The third option is clearest if the action does both.

Recommended:

```text
Primary CTA: one blue button only
Secondary actions: dark cards or outline buttons
Danger or warning actions: not blue
```

---

## Quick Log

### Problems

The Quick Log section is too large and visually busy.

* It uses 8 icons, each with a different color.
* The labels are small.
* The icon circles are visually heavy.
* It consumes a large vertical block before the user sees weekly stats.
* It is unclear whether quick logs are available before the session starts.
* “Brief Wake” in the same grid as Bathroom, Water, Pain, Dream is conceptually mixed. Some are events, some are symptoms, some are environment notes.

### Fix

Use a collapsible or horizontal quick log.

Better:

```text
Quick Log
[Bathroom] [Water] [Lights out] [Pain] [+ More]
```

Then put the rest in a modal.

Recommended:

```text
Visible quick actions: 4 or 5 max
Grid height: 96 to 120 pt max
Icon size: 36 to 44 pt
Label size: 11 to 12 pt
Section padding: 12 to 16 pt
```

Do not show 8 colorful buttons unless quick logging is the main purpose of the screen.

Also consider grouping:

```text
Common: Bathroom, Water, Lights out, Brief wake
Symptoms: Anxiety, Noise, Pain, Dream
```

---

## Yellow “Wake Up & End Session” card

### This card is too visually aggressive.

Yellow is the loudest color on the screen. It should not be used for an end-session action unless that is the current primary state.

Problems:

* It is huge.
* It appears before the dose/status summary.
* It competes with “Take Dose 1”.
* The text wraps heavily.
* Centered multiline copy makes the card feel less polished.
* The chevron floats awkwardly at the far right.

### Fix

Only show this card in morning-closeout state.

If it must appear now, reduce it:

```text
End session
Complete morning check-in
```

Recommended design:

```text
Use dark card background
Use yellow icon or small accent
Height: 72 to 88 pt
Left-aligned text
Chevron aligned center-right
```

Avoid full yellow fill unless the entire current state is “morning closeout.”

---

## Dose status strip

### Problems

This strip looks like a bottom navigation bar but is placed mid-page.

* It has icons, labels, counts, vertical separators, and small text.
* It feels like a tab bar, not session status.
* Dose 1 and Dose 2 show dashes, Events shows 0, Snooze shows 0/3. The meaning is not immediately clear.
* It competes with the actual content below.

### Fix

Make it either:

1. A sticky bottom session status bar, or
2. A compact status row inside the active session card.

Better:

```text
Dose 1       Dose 2       Events       Snoozes
Not taken    Not taken    0            0 of 3
```

Use text over icons here. The current icon treatment is too cryptic.

Recommended:

```text
Height: 64 to 72 pt
No vertical dividers unless alignment is very strict
Use one muted card background
Use 13 to 15 pt labels
Use 16 to 18 pt values
```

---

## “This Week” card

### Problems

This section is decent, but it is in the wrong place.

* Weekly adherence is not as urgent as tonight’s action.
* “29%” with a red icon is visually alarming.
* “7/7 tracked” and “3 skipped this week” may be valuable, but they add cognitive load during dosing.
* The stat boxes feel cramped.
* The card appears before “Dose Intervals,” creating a dashboard feel inside the home screen.

### Fix

Collapse it on the home screen.

Better:

```text
This week
29% adherence, 3 skipped
View insights
```

Or move the full card to an Insights tab.

If kept:

```text
Show 2 stats max on home
Move Avg interval and Streak to detail screen
Use less saturated red unless this is a clinical warning
```

---

## “Dose Intervals” card

### Problems

This card looks orphaned.

* It is narrower than the cards above.
* It is horizontally centered, which breaks the layout grid.
* It appears after the weekly card, but it has no clear relationship to the active session.
* “No dose intervals yet” is empty-state content that should probably not occupy space unless the section matters.

### Fix

Either remove it from the home screen or make it part of the weekly insights card.

Better:

```text
Dose intervals
No intervals yet
```

as a full-width row inside Insights, not as a floating mini-card.

On this home screen, I would remove it.

---

## Color system

The screen currently uses too many saturated blocks:

```text
Orange
Blue
Purple
Blue again
Yellow
Green
Red
Cyan
Multiple icon colors
```

This makes the interface feel noisy and less trustworthy.

Use color by meaning:

```text
Blue: primary action
Green: success or positive timing
Orange: warning that needs attention
Red: error or missed dose
Yellow: caution, use sparingly
Purple: optional reflection/check-in, not primary
Gray: secondary cards
```

Rule:

```text
Only one full-width saturated action card visible at a time.
```

Right now there are at least four.

---

## Spacing system

The spacing is inconsistent. Some cards are tightly stacked, some have bigger gaps, and the final card breaks the horizontal grid.

Use a fixed spacing system:

```text
Screen horizontal margin: 16 pt
Card vertical gap: 12 pt
Section gap: 20 pt
Card padding: 16 pt
Small internal gap: 4 pt
Medium internal gap: 8 pt
Large internal gap: 12 pt
Corner radius: 16 pt
```

Specific corrections:

* Use the same left and right edge for every card.
* Do not let “Dose Intervals” use a smaller width unless it is part of a deliberate grid.
* Keep all major cards full width.
* Keep primary buttons at 56 pt height.
* Keep secondary cards under 88 pt unless they contain real data.
* Do not use tall action cards for simple actions.

---

## Vertical span problem

This screen is too tall. On a normal phone, the user will not see the full experience without a long scroll. The screen likely spans far beyond a practical first-view dashboard.

Above the fold, the user should see:

```text
Header
Important alert, only if needed
Sleep plan summary
One primary action
Small status row
```

Everything else should be below or collapsed.

Current above-the-fold content is too fragmented. The primary action is buried between multiple competing cards.

Target first screen:

```text
DoseTap
Tonight, Fri Jun 12

Finish previous check-in
Jun 11 is incomplete
[Finish]

Sleep Plan
Wake 7:00 AM
Wind down in 3h 15m
Bed 10:45 PM

[Start tonight]
```

That is enough.

---

## Text wrapping

Several labels are wrapping in ways that make the UI feel unpolished.

Bad wrapping examples:

```text
Complete
check-in for
Jun 11

Wake Up &
End Session

Complete your morning
check-in

Sleep if in
bed now
```

Fix with shorter labels:

```text
Finish Jun 11 check-in
End session
Morning check-in
If in bed now
Sleep window
Wake 7:00 AM
```

Use these rules:

```text
Primary button labels: 1 line only
Card titles: 1 line preferred, 2 max
Card subtitles: 2 lines max
Metric labels: 1 to 2 words when possible
Do not center-align multiline operational copy
```

Left-align most action cards. Centered multiline text is one reason the yellow card feels clumsy.

---

## Typography

The typography is inconsistent in visual weight.

Problems:

* Some large labels are too bold.
* Some disabled labels are nearly invisible.
* The card titles compete with the app title.
* Small labels in Quick Log and status strip may be hard to read.
* Time formatting lacks spacing, for example “7:00AM”.

Recommended scale:

```text
App title: 34 pt bold
Screen date: 17 pt semibold
Card title: 20 to 22 pt semibold
Card body: 15 to 17 pt regular
Metric label: 13 to 15 pt medium
Metric value: 21 to 24 pt semibold
Button text: 18 to 20 pt semibold
Quick Log label: 11 to 12 pt medium
```

Time format:

```text
7:00 AM
10:45 PM
10:25 PM
```

Use a space before AM and PM.

---

## Accessibility

This screen has several likely accessibility problems.

* Low-contrast disabled text on blue and purple cards.
* Small Quick Log labels.
* Some meaning is color-only.
* The close X on the orange card may not have a reliable 44 pt tap target.
* The small status strip values may not survive larger Dynamic Type.
* The multi-column sleep metrics will break under larger text.
* The Quick Log grid will become crowded with larger accessibility fonts.

Fixes:

```text
Minimum tap target: 44 x 44 pt
Do not rely on color alone
Avoid opacity below readable contrast
Support Dynamic Type by stacking metric columns on larger text sizes
Keep primary actions one line at standard sizes
```

For larger text, Sleep Plan should change from 3 columns to stacked rows:

```text
Bedtime: 10:45 PM
Wind-down: 10:25 PM
Sleep window: 11h 35m
```

---

## Recommended revised home layout

A cleaner version of this screen:

```text
DoseTap                                      settings icon
Tonight, Fri Jun 12

[Incomplete session]
Finish Jun 11 check-in                       Finish

[Sleep Plan]
Wake 7:00 AM
Wind down in 3h 15m
Bed 10:45 PM     Wind-down 10:25 PM     Sleep 11h 35m

[Start tonight] or [Take Dose 1]

[Quick Log]
Bathroom     Water     Lights out     Pain     More

[Dose Status]
Dose 1: Not taken     Dose 2: Not taken
Events: 0             Snoozes: 0 of 3

[This Week]
29% adherence, 3 skipped                     View
```

What I would remove from this screen:

```text
Full Dark toggle
Large Just for tonight card
Tap below to start card
Full purple pre-sleep check card
Full yellow end-session card unless it is morning
Floating Dose Intervals card
Full weekly analytics card
```

---

## Concrete priority list

Fix in this order:

1. Remove conflicting actions. Show only one primary action.
2. Turn the orange card into a compact warning banner.
3. Delete the “Tap below to start” card.
4. Move the Dark toggle to Settings.
5. Reduce “Just for tonight” to a 64 to 76 pt settings row.
6. Only show “Wake Up & End Session” during morning closeout.
7. Collapse Quick Log to 4 or 5 visible actions plus More.
8. Move full weekly analytics to an Insights tab.
9. Make all cards share the same horizontal width.
10. Replace awkward wrapped copy with shorter labels.

## Bottom line

The app does not need more decoration. It needs stricter state-based rendering. The current design makes too many things visible at once, which weakens trust and creates the feeling that the app itself is unsure what state the user is in.

The strongest redesign move is this:

```text
One screen state.
One primary action.
One source of truth for what appears.
Everything else secondary or hidden.
```

#####



Those refinements are valid. I would not treat them as minor. They expose three implementation requirements I did not specify tightly enough:

1. The screen needs defined  **state transitions** , not just static states.
2. Quick Log needs a defined  **sheet interaction model** , not just “move it to a modal.”
3. Theme handling should default to  **system appearance** , with manual override only in Settings.

Here is the updated revised version.

# Updated design logic before code

## 1. Define the home screen state machine

Do not build the home screen from scattered booleans like:

```text
hasIncompleteSession
isDoseReady
hasStartedTonight
canEndSession
hasQuickLogEvents
showWeeklyStats
```

That is how the UI ends up showing start, dose, check-in, and end-session actions at the same time.

Use one resolved presentation state:

```swift
enum HomePresentationState {
    case previousSessionNeedsReview
    case tonightNotStarted
    case activeSession
    case doseReady
    case dosePending
    case morningCloseout
    case reviewOnly
}
```

The UI should render from that one state. Supporting data can exist, but it should not independently decide what appears.

Example:

```text
DoseSessionRepository
        ↓
HomeStateResolver
        ↓
HomePresentationState
        ↓
DoseTapHomeView
```

The screen should not ask five different services what to show. That recreates UI split brain.

---

## 2. Define transitions between states

Static layout is not enough. The user will feel the app change state during the night, after a button tap, after a Flic press, after a notification, or after midnight. Those transitions need rules.

### Transition map

| From state                     |                              Trigger | To state                                    | UI behavior                                                    |
| ------------------------------ | -----------------------------------: | ------------------------------------------- | -------------------------------------------------------------- |
| `previousSessionNeedsReview` |           User finishes old check-in | `tonightNotStarted`or `activeSession`   | Alert collapses vertically, tonight card moves up smoothly     |
| `tonightNotStarted`          |              User taps Start Tonight | `activeSession`                           | Start CTA morphs into Dose 1 area, do not reload entire screen |
| `activeSession`              |                    Dose window opens | `doseReady`                               | Dose CTA becomes primary, status row updates in place          |
| `doseReady`                  |                  User taps Take Dose | `dosePending`                             | Button shows pending state, disables duplicate taps            |
| `dosePending`                |           Repository commit succeeds | `activeSession`                           | Dose status updates, Undo snackbar appears                     |
| `dosePending`                |                         Commit fails | `doseReady`                               | Button returns, error shown inline                             |
| `activeSession`              |       Morning closeout becomes valid | `morningCloseout`                         | End Session replaces dose CTA, not added below it              |
| `morningCloseout`            |                    User ends session | `reviewOnly`or next `tonightNotStarted` | Closeout card collapses, summary appears                       |
| Any state                      | External Flic or notification action | Re-resolved state                           | Animate affected card only, show source note if useful         |

Important: the UI should not animate to “dose taken” until the command path commits:

```text
DoseActionCoordinator -> SessionRepository -> EventStorage -> snapshot update
```

For a medication tracker, optimistic UI is risky unless rollback is extremely clear. Safer behavior:

```text
Tap Take Dose 1
Button becomes “Saving...”
Repository commits event and snapshot
Button becomes “Dose 1 taken”
Undo appears
```

---

## 3. Animation rules

Use restrained transitions. This app is likely used at night, possibly while tired. Motion should clarify state, not decorate it.

Recommended rules:

```text
Card insertion/removal: fade plus vertical collapse
Duration: 180 to 260 ms
Primary CTA change: morph label and color in place when possible
Do not animate the whole scroll view
Do not jump scroll position unless a blocking alert appears
Respect Reduce Motion
```

Specific recommendations:

### Previous session resolved

When the user finishes the Jun 11 check-in:

```text
Orange alert shrinks upward
Sleep Plan moves up
Primary CTA stays anchored
No full screen refresh
```

### Start tonight

When the user taps Start Tonight:

```text
Start Tonight button becomes Saving...
On commit, it changes to Take Dose 1 or Dose 1 pending
Quick Log fades in below
Session Status appears below Quick Log
```

Do not show both:

```text
Ready for Dose 1
Take Dose 1
```

as separate full-width blocks.

### Dose taken

When Dose 1 is recorded:

```text
Take Dose 1 -> Saving... -> Dose 1 taken
Status row updates
Undo snackbar appears for a short window
```

Undo should be visually tied to the committed dose event, not floating as a generic action.

### Morning closeout

When the app enters morning closeout:

```text
Take Dose card is removed or demoted
End Session becomes the primary CTA
Weekly summary stays collapsed
```

Do not show “Take Dose 1” and “Wake Up & End Session” as equal actions unless that is truly valid.

---

## 4. Clarify incomplete-session behavior

My earlier version treated the incomplete session as a blocking item. That needs a stricter rule.

Do not block medication logging just because yesterday’s check-in is incomplete unless the unresolved prior session affects the current session identity.

Use this rule:

```text
If prior check-in affects session_id, rollover, or dose state:
    show blocking alert before current actions.

If prior check-in is only missing survey or notes:
    show compact non-blocking banner.
```

Better banner copy:

```text
Finish previous check-in
Jun 11 is incomplete.                      Finish
```

Avoid:

```text
Incomplete Session
Complete
Complete check-in for Jun 11
Complete
X
```

That wording is repetitive and visually stressful.

---

# Updated Quick Log modal model

## 1. Home screen Quick Log

The home screen should show only the most common actions:

```text
Quick Log
Bathroom    Water    Lights out    Pain    More
```

This keeps the home screen usable.

Visible quick logs should work as direct actions:

```text
Tap Bathroom
Event logs immediately
Small confirmation appears: Bathroom logged
Undo available
```

Do not open a modal for the top 4 or 5 actions. That adds friction.

---

## 2. More opens a bottom sheet

Use a bottom sheet, not a full-screen modal.

Recommended sheet:

```text
Title: Quick Log
Subtitle: Add an event to this session
Drag handle at top
Close X in top-right
Done button at bottom or top-right
Swipe down to dismiss
```

Use both swipe dismissal and explicit close. Swipe-only dismissal is bad for accessibility and discoverability.

Suggested layout:

```text
Quick Log                              X

Common
Bathroom       Water
Lights out     Brief wake

Symptoms
Anxiety        Pain
Noise          Dream

Other
Add note
```

Recommended sizing:

```text
Sheet default detent: medium
Expanded detent: large
Tap target: 56 x 56 pt minimum
Label: 13 to 15 pt
Icon: 28 to 34 pt
```

---

## 3. Logging inside the sheet

Do not auto-dismiss immediately after every tap. That is fast for one event but annoying when the user needs to log multiple events, which is likely at night.

Better behavior:

```text
Tap event
Item shows checkmark
Toast says “Pain logged”
Undo appears
Sheet remains open
User taps Done or swipes down
```

For the home-row quick actions, immediate log plus snackbar is fine.

For the expanded sheet, keep it open for batch logging.

---

## 4. Duplicate protection

Quick Log needs accidental duplicate protection.

Rules:

```text
Disable the tapped item for 700 to 1000 ms after logging.
Use an idempotency key for the command.
If the same event is tapped twice within a short window, show “Already logged. Tap again to add another.”
```

This matters for tired users and for repeated taps caused by lag.

---

## 5. Sheet dismissal and data safety

The sheet should not have unsaved local state for basic event taps. Each tap should commit through the same command path:

```text
QuickLogSheet -> DoseActionCoordinator -> SessionRepository -> EventStorage
```

That means dismissal is safe:

```text
Swipe down: closes sheet
X: closes sheet
Done: closes sheet
Tap outside: closes sheet, if supported
```

No “Are you sure?” prompt unless there is an unsaved note field.

For a note field:

```text
Unsaved note present
User dismisses
Show: Save note, Discard, Cancel
```

---

# Updated theme logic

## 1. Default to system theme

The app should respect the OS appearance by default.

Settings should offer:

```text
Appearance
System
Light
Dark
```

Default:

```text
System
```

The home screen should not show a full “Dark” toggle. It is not part of the nightly dose workflow.

---

## 2. Manual override only in Settings

Use this behavior:

```text
System: follow iOS appearance
Light: force light mode
Dark: force dark mode
```

In SwiftUI terms:

```swift
enum AppearanceMode: String, Codable {
    case system
    case light
    case dark
}
```

Conceptual behavior:

```text
system -> preferredColorScheme nil
light -> preferredColorScheme .light
dark -> preferredColorScheme .dark
```

Do not hard-code colors against dark mode only. Use semantic color tokens.

---

## 3. Color tokens

Create app-level semantic tokens instead of raw colors scattered through views.

Example:

```text
backgroundPrimary
backgroundCard
textPrimary
textSecondary
textMuted
accentPrimary
accentWarning
accentDanger
accentSuccess
borderSubtle
buttonPrimaryBackground
buttonPrimaryText
```

This prevents light mode from becoming an afterthought.

Also test:

```text
System light
System dark
Manual light
Manual dark
Increased contrast
Reduce transparency
Reduce motion
Large Dynamic Type
```

---

## 4. Migration behavior

If existing users already selected Dark manually, preserve that preference.

Suggested migration:

```text
Existing dark toggle on -> Appearance: Dark
Existing dark toggle off -> Appearance: System
New installs -> Appearance: System
```

Do not surprise current users by flipping them into light mode.

---

# Updated final layout spec

For the screenshot state, assuming prior check-in does not block medication logging:

```text
DoseTap                                      settings icon
Tonight, Fri Jun 12

Finish previous check-in
Jun 11 is incomplete.                       Finish

Sleep Plan
Wake 7:00 AM
Wind down in 3h 15m

Bedtime       Wind-down       Sleep window
10:45 PM      10:25 PM        11h 35m

Just for tonight                             toggle
Use typical wake time, 7:00 AM

Take Dose 1
Dose 1 is ready

Quick Log
Bathroom    Water    Lights out    Pain    More

Session Status
Dose 1: Not taken       Events: 0
Dose 2: Not taken       Snoozes: 0 of 3

This Week
29% adherence, 3 skipped                    View
```

For the screenshot state, assuming prior check-in does affect session identity:

```text
DoseTap                                      settings icon
Tonight, Fri Jun 12

Finish previous session
Jun 11 must be completed before tonight starts.
[Finish check-in]

Sleep Plan
Wake 7:00 AM
Wind down in 3h 15m

Primary dose actions hidden or disabled until resolved
```

That distinction matters. Do not block current medication logging for a stale survey unless there is a real data-integrity reason.

---

# Add these requirements before coding

## State and transition requirements

```text
Home screen renders from one HomePresentationState.
Every state transition has a defined visual transition.
External actions from Flic, notification, and deep link re-resolve the same state.
Do not show start, dose, and end-session CTAs at the same time.
Do not animate dose completion until repository commit succeeds.
Respect Reduce Motion.
```

## Quick Log requirements

```text
Top 4 or 5 logs are direct actions.
More opens a bottom sheet.
Sheet supports swipe down, X, and Done.
Taps commit immediately through DoseActionCoordinator.
Sheet stays open for batch logging.
Undo is available after each log.
Duplicate taps are throttled and idempotent.
```

## Theme requirements

```text
Default appearance is System.
Manual Light and Dark live in Settings.
Home screen has no full theme toggle.
Use semantic color tokens.
Preserve existing Dark users during migration.
Test light, dark, contrast, Dynamic Type, and Reduce Motion.
```

## Revised bottom line

The next design pass should not just adjust spacing. It should define:

```text
What state the user is in.
What transition just happened.
What one action is primary.
What secondary tools are available.
What gets hidden until relevant.
```

Your three refinements close the gap between visual critique and implementation-ready design logic.

Confidence: 98%.
