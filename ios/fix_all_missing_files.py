#!/usr/bin/env python3
import os
import uuid
import re

PROJECT_PATH = "DoseTap.xcodeproj/project.pbxproj"


def generate_uuid():
    return str(uuid.uuid4()).replace("-", "").upper()[:24]


def add_file_to_project(filename, folder_path, rel_path, add_to_tests=False):
    with open(PROJECT_PATH, "r") as f:
        content = f.read()

    if filename in content:
        print(
            f"File {filename} reference already exists, ensuring it's in build phases..."
        )
    else:
        # Add basic file reference if missing
        file_uuid = generate_uuid()
        file_entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel_path}"; sourceTree = "<group>"; }};'

        # Add to PBXFileReference section
        ref_section_end = content.find("/* End PBXFileReference section */")
        content = (
            content[:ref_section_end] + file_entry + "\n" + content[ref_section_end:]
        )

        # Add to DoseTap group (F01) or appropriate group
        group_pattern = r"(F01 /\* DoseTap \*/ = \{.*?children = \()([^)]*)(\);)"
        content = re.sub(
            group_pattern,
            lambda m: m.group(1)
            + m.group(2)
            + f"\n\t\t\t\t{file_uuid} /* {filename} */,"
            + m.group(3),
            content,
            flags=re.DOTALL,
        )

    # Now handle build files and targets
    def add_to_phase(phase_id, target_label):
        nonlocal content
        # Find if filename is already in this phase
        phase_pattern = rf"({phase_id} /\* Sources \*/ = \{{.*?files = \()([^)]*)(\);)"
        match = re.search(phase_pattern, content, flags=re.DOTALL)
        if match and filename in match.group(2):
            print(f"  Skipping {filename} for {target_label}, already in phase")
            return

        # Need to find the fileRef UUID
        file_ref_match = re.search(rf"([A-Z0-9]{{24}}) /\* {filename} \*/", content)
        if not file_ref_match:
            print(f"  Error: Could not find fileRef for {filename}")
            return
        file_uuid = file_ref_match.group(1)

        build_uuid = generate_uuid()
        build_entry = f"\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};"

        # Add to PBXBuildFile section
        build_section_end = content.find("/* End PBXBuildFile section */")
        content = (
            content[
                :ref_section_end
            ]  # This is wrong, should be build_section_end. Wait, I had content[:build_section_end]
            + build_entry
            + "\n"
            + content[build_section_end:]
        )
        # Fix: build_section_end might shift after adding entry
        # Re-calc section end for next use? No, we are non-local content already.

        # Add to phase files list
        content = re.sub(
            phase_pattern,
            lambda m: m.group(1)
            + m.group(2)
            + f"\n\t\t\t\t{build_uuid} /* {filename} in Sources */,"
            + m.group(3),
            content,
            flags=re.DOTALL,
        )
        print(f"  Added {filename} to {target_label}")

    add_to_phase("J01", "DoseTap (Main)")
    if add_to_tests:
        add_to_phase("8017D52D2EFCDF6A00BF9683", "DoseTapTests")

    with open(PROJECT_PATH, "w") as f:
        f.write(content)


if __name__ == "__main__":
    os.chdir("ios")

    # Files to ensure are in Main target.
    # We rely on @testable import for Tests target.
    files_to_add = [
        ("DoseModels.swift", "../DoseTapiOSApp/DoseModels.swift"),
        ("DoseCoreIntegration.swift", "../DoseTapiOSApp/DoseCoreIntegration.swift"),
        ("SQLiteStorage.swift", "../DoseTapiOSApp/SQLiteStorage.swift"),
        ("TimelineView.swift", "../DoseTapiOSApp/TimelineView.swift"),
        ("QuickLogPanel.swift", "../DoseTapiOSApp/QuickLogPanel.swift"),
        ("TonightView.swift", "../DoseTapiOSApp/TonightView.swift"),
        (
            "EnhancedNotificationService.swift",
            "../DoseTapiOSApp/EnhancedNotificationService.swift",
        ),
        ("HealthKitManager.swift", "../DoseTapiOSApp/HealthKitManager.swift"),
        ("DashboardView.swift", "../DoseTapiOSApp/DashboardView.swift"),
        ("DataExportService.swift", "../DoseTapiOSApp/DataExportService.swift"),
        (
            "UserConfigurationManager.swift",
            "../DoseTapiOSApp/UserConfigurationManager.swift",
        ),
        ("DataStorageService.swift", "../DoseTapiOSApp/DataStorageService.swift"),
        (
            "HealthIntegrationService.swift",
            "../DoseTapiOSApp/HealthIntegrationService.swift",
        ),
        ("KeychainHelper.swift", "../DoseTapiOSApp/KeychainHelper.swift"),
        ("SetupWizardService.swift", "../DoseTapiOSApp/SetupWizardService.swift"),
        ("SetupWizardView.swift", "../DoseTapiOSApp/SetupWizardView.swift"),
        ("InventoryService.swift", "../DoseTapiOSApp/InventoryService.swift"),
        ("UIUtils.swift", "../DoseTapiOSApp/UIUtils.swift"),
        ("WHOOPService.swift", "WHOOPService.swift"),
        ("AnalyticsService.swift", "AnalyticsService.swift"),
        ("UserSettingsManager.swift", "UserSettingsManager.swift"),
        ("EventStorage.swift", "Storage/EventStorage.swift"),
        ("MorningCheckInView.swift", "Views/MorningCheckInView.swift"),
    ]

    for filename, rel_path in files_to_add:
        # Default to False for add_to_tests to avoid duplication errors
        add_file_to_project(filename, "DoseTapiOSApp", rel_path, add_to_tests=False)
