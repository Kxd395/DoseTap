#!/usr/bin/env python3
import os
import sys
import uuid

# Generate unique IDs for the new files
sleep_plan_view_fileref = str(uuid.uuid4())[:24].upper().replace('-', '')
sleep_plan_view_buildfile = str(uuid.uuid4())[:24].upper().replace('-', '')
diag_log_view_fileref = str(uuid.uuid4())[:24].upper().replace('-', '')
diag_log_view_buildfile = str(uuid.uuid4())[:24].upper().replace('-', '')

project_path = "DoseTap.xcodeproj/project.pbxproj"

with open(project_path, 'r') as f:
    content = f.read()

# Add build file entries after the last PBXBuildFile
build_file_section = f"""\t\t{sleep_plan_view_buildfile} /* SleepPlanDetailView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {sleep_plan_view_fileref} /* SleepPlanDetailView.swift */; }};
\t\t{diag_log_view_buildfile} /* DiagnosticLoggingSettingsView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {diag_log_view_fileref} /* DiagnosticLoggingSettingsView.swift */; }};
/* End PBXBuildFile section */"""

content = content.replace("/* End PBXBuildFile section */", build_file_section)

# Add file reference entries after the last PBXFileReference  
file_ref_section = f"""\t\t{sleep_plan_view_fileref} /* SleepPlanDetailView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SleepPlanDetailView.swift; sourceTree = "<group>"; }};
\t\t{diag_log_view_fileref} /* DiagnosticLoggingSettingsView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DiagnosticLoggingSettingsView.swift; sourceTree = "<group>"; }};
/* End PBXFileReference section */"""

content = content.replace("/* End PBXFileReference section */", file_ref_section)

# Find DoseTap group and add files
# Look for the pattern with SettingsView.swift
settings_view_pattern = "B358CDCA949364F93BD996D6 /* SettingsView.swift */,"
if settings_view_pattern in content:
    new_files = f"""{settings_view_pattern}
\t\t\t\t{sleep_plan_view_fileref} /* SleepPlanDetailView.swift */,
\t\t\t\t{diag_log_view_fileref} /* DiagnosticLoggingSettingsView.swift */,"""
    content = content.replace(settings_view_pattern, new_files)

# Find Sources build phase and add build files
# Look for SettingsView.swift in Sources
sources_pattern = "626911F284B24C54BA73D7F8 /* SettingsView.swift in Sources */,"
if sources_pattern in content:
    new_sources = f"""{sources_pattern}
\t\t\t\t{sleep_plan_view_buildfile} /* SleepPlanDetailView.swift in Sources */,
\t\t\t\t{diag_log_view_buildfile} /* DiagnosticLoggingSettingsView.swift in Sources */,"""
    content = content.replace(sources_pattern, new_sources)

with open(project_path, 'w') as f:
    f.write(content)

print("Added SleepPlanDetailView.swift and DiagnosticLoggingSettingsView.swift to project")
