# Repository and Cache Hygiene

Status: Current repository runbook
Last verified: 2026-09-02

This runbook defines the safe, repository-local checks for Git refs, Finder metadata, ignore rules, and disposable build caches. It does not authorize broad deletion of Git objects, source files, application data, or simulator/device data.

## Required check

Run from the repository root:

```bash
bash tools/check_repository_hygiene.sh
```

The check fails when Finder metadata is tracked, when `.DS_Store` appears anywhere under `.git/refs`, when active `.gitignore` rules are duplicated, when required secret/metadata ignore rules are missing, or when `git fsck --full` reports an invalid ref. Dangling Git objects are counted and reported but are not deleted; they are common after rebases and local checkpointing.

CI runs the same check so a clean checkout must satisfy the same contract as a developer checkout.

## Invalid-ref recovery

On 2026-09-01, the three known invalid ref files were validated as regular Apple Desktop Services Store files, copied byte-for-byte to `.git/dosetap-recovery/invalid-refs-2026-09-01`, and then removed from these exact paths:

- `.git/refs/.DS_Store`
- `.git/refs/heads/.DS_Store`
- `.git/refs/remotes/.DS_Store`

The remote-ref list was identical before and after removal, and `git fsck --full` returned success with no invalid-ref diagnostics. The recovery copies are intentionally outside `.git/refs`; copying them back would restore the corruption and is only appropriate for forensic inspection.

If the problem recurs, stop and validate the exact paths, file types, count, and legitimate refs before changing anything. Never run a recursive delete across `.git`, `.git/refs`, or `.git/objects`. Keep recovery copies outside the ref namespace and compare `git for-each-ref` output before and after any repair.

The committed `.gitignore` prevents Finder metadata from entering the source history. The repository check prevents unnoticed `.git/refs` contamination from being treated as a healthy checkout. Finder may still create local metadata on mounted volumes, so the check remains the enforcement point without changing workstation-wide preferences.

## Cache inspection

Measure known disposable build outputs before deciding to clean them:

```bash
du -sh .build .xcode-derived ios/build ios/DoseTap/.build macos/DoseTapStudio/.build 2>/dev/null || true
```

Do not clean while Xcode, SwiftPM, or CI commands are running. Prefer each build system's reviewed cleanup command rather than deleting directories manually:

```bash
swift package clean
(cd ios/DoseTap && swift package clean)
(cd macos/DoseTapStudio && swift package clean)
xcodebuild clean \
  -project ios/DoseTap.xcodeproj \
  -scheme DoseTap \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PWD/.xcode-derived"
```

These commands remove reproducible build products. They do not remove repository source, the Git object database, local `.env` configuration, iOS Simulator content, signed-device content, or the app's on-device SQLite data. Rebuild with `swift build`, `swift test`, and the simulator command in the root README.
