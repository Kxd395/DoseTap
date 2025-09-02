# Agent Brief: DoseTap

## Goal
Implement a minimal iOS/watchOS app that logs Dose 1 / Dose 2 / Bathroom and schedules a local notification for Dose 2 at a data-informed minute strictly inside 2.5–4 hours after Dose 1.

## Constraints
- Never schedule outside [150, 240] minutes after Dose 1.
- Use HealthKit sleep to compute TTFW median baseline; add small same-night nudges.
- WHOOP API is for history (not live staging).

## Deliverables
- URL scheme handler: `dosetap://log?event=...`
- Reminder scheduler
- HealthKit read (sleep)
- WHOOP OAuth scaffolding
- Watch app with three buttons
- Insights view + CSV export
