# TestFlight distribution guide

Status: Current external-service runbook
Last verified against Apple documentation: 2026-09-02

This procedure uploads the shipping `DoseTap` iPhone target. It does not enable the staging CloudKit path and does not grant production readiness.

## Prerequisites

- An App Store Connect app record for bundle ID `com.dosetap.ios` must exist before upload.
- The person uploading needs an App Store Connect role that Apple permits to upload builds.
- Current agreements, signing certificates, provisioning profiles, privacy disclosures, export-compliance answers, and required metadata must be ready.
- The release commit must pass `docs/PRODUCTION_READINESS_CHECKLIST.md` and `docs/RELEASE_CHECKLIST.md`.
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must identify a new upload as required by App Store Connect.

Apple's current references:

- [Create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)

## 1. Validate the release candidate

From the repository root:

```bash
bash tools/check_app_version.sh
bash tools/release_preflight.sh vX.Y.Z
```

Use the real approved release environment. Do not put credentials or certificate pins into this document.

## 2. Open the correct Xcode project

```bash
open ios/DoseTap.xcodeproj
```

Select the `DoseTap` scheme and a generic or connected iOS device. A simulator destination cannot produce an archive for upload.

## 3. Archive

In Xcode, choose Product > Archive. When the build succeeds, Xcode opens the archive in Window > Organizer > Archives.

Command-line archive creation is available when signing is already configured:

```bash
xcodebuild clean archive \
  -project ios/DoseTap.xcodeproj \
  -scheme DoseTap \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/DoseTap.xcarchive \
  -allowProvisioningUpdates
```

Inspect the archive's bundle ID, version, build number, entitlements, privacy manifest, symbols, and signing identity before upload.

## 4. Upload with Xcode

Apple's current Xcode workflow is:

1. Select the archive in Organizer.
2. Choose Distribute App.
3. Choose App Store Connect.
4. Choose Upload.
5. Review distribution and signing options.
6. Review the certificate, provisioning profile, and entitlements.
7. Upload.

See [Upload an app to App Store Connect](https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html).

Transporter and authenticated command-line upload options also exist, but Xcode Organizer is the maintained default for this project. Do not place an Apple Account password in a shell command or repository file.

## 5. Wait for processing and review warnings

The upload must finish processing before it can be assigned to testers. In App Store Connect, open the TestFlight tab and review build status, warnings, export-compliance state, and crash-symbol availability. A `Complete` upload status is not product acceptance.

## 6. Configure testing

- Provide beta description, feedback contact, and what-to-test notes.
- Assign the processed build to the intended internal or external group.
- External testing may require Beta App Review.
- Confirm supported device and OS coverage from the build metadata.
- Record which build, group, and acceptance script each tester used.

Apple currently permits up to 100 internal App Store Connect users and up to 10,000 external testers. A TestFlight build is testable for up to 90 days. Recheck those limits in Apple's TestFlight overview before relying on them.

## 7. DoseTap acceptance

TestFlight distribution must retain explicit evidence for:

- committed Dose 1 and Dose 2 surviving process termination;
- notification scheduling and recovery;
- Apple Health permission and real-data states;
- Dashboard, History, Night Review, and export parity for the same night;
- timezone display and travel behavior;
- Clear All Data and credential disconnect behavior;
- VoiceOver, Dynamic Type, contrast, and reduced motion;
- crash and diagnostic review without health-data leakage.

Record failures in Plane. Do not reconstruct missing medication records from indirect evidence.
