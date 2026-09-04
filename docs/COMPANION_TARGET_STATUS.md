# Companion Target Status

Status: Current companion-target authority
Last verified: 2026-09-02
Authority: `docs/SSOT/contracts/companion-targets.json`

## Current product status

DoseTap ships one supported application target: the iPhone app. No watchOS app, watch complication, Home Screen widget, or Lock Screen widget is currently supported or included as a companion target.

The repository previously contained product-shaped watchOS and WidgetKit source without the targets, schemes, App Group entitlements, signing configuration, CI builds, or physical acceptance evidence required to ship it. The widget files were compiled as inert source in the phone app rather than as a Widget Extension. That state was neither a working companion feature nor an honest deferred proposal.

On 2026-09-01, the source was moved out of the shipping trees and Xcode project into:

- `proposals/companions/watchos/DoseTapWatch`
- `proposals/companions/widget`

The proposal source is retained for design reference only. It is not compiled, packaged, installed, or covered by product support. Core package support for the watchOS platform does not create a watch app target.

## CI contract

`tools/check_companion_targets.sh` reads the SSOT manifest and enforces all of the following:

- `supported_targets` is empty while status is `proposal_only`;
- no companion source exists under `watchos/DoseTapWatch` or `ios/DoseTap/Widget`;
- proposal source remains available outside the shipping tree;
- the Xcode project has no watch, widget, or complication target/scheme and no proposal file references;
- the iPhone source tree does not import companion-only frameworks.

CI therefore builds every supported companion target: there are currently zero. Adding a name to the manifest deliberately fails the guard until a reviewed CI build matrix and acceptance plan are implemented.

## Promotion requirements

Promoting either proposal to supported product work requires a new bounded Plane item and architecture review. It must include:

1. dedicated Xcode application/extension targets and shared schemes;
2. explicit bundle identifiers, App Group scope, entitlements, signing, deployment targets, and privacy disclosure;
3. one canonical read model derived from committed phone state;
4. no independent watch/widget medication state machine;
5. all medication actions routed back through the phone's `DoseActionCoordinator`, with denial, offline, idempotency, and conflict behavior defined;
6. characterization tests for the 150-minute and 240-minute boundaries, skip/snooze, stale state, timezone changes, restart, and unavailable-phone behavior;
7. CI builds/tests for every promoted target and verifies the archive contains the intended extensions;
8. owner-observed installation, timeline refresh, state parity, accessibility, and offline behavior on a real supported watch/device.

Until those gates are met, roadmap and release notes must use “proposal-only” or “deferred,” never “implemented,” “resolved,” or “shipped.”

## Rollback

The source move can be reversed by moving the proposal trees back and restoring the removed project references. Doing only that would recreate the orphaned state and is not a valid feature activation. A rollback that restores shipping references must also reopen DOSETAP-18.
