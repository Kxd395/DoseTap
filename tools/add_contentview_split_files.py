#!/usr/bin/env python3
"""Add the ContentView split files to the Xcode project."""
import uuid
import re
import sys

# Files to add (relative to DoseTap/ directory)
new_files = [
    "EventLogger.swift",
    "Views/TonightView.swift",
    "Views/SleepPlanCards.swift",
    "Views/CompactStatusCard.swift",
    "Views/CompactDoseButton.swift",
    "Views/SessionSummaryViews.swift",
    "Views/QuickEventViews.swift",
    "Views/DetailsView.swift",
]

PROJ = "ios/DoseTap.xcodeproj/project.pbxproj"

def gen_id():
    return uuid.uuid4().hex.upper()[:24]

def main():
    with open(PROJ, "r") as f:
        content = f.read()

    build_ids = []
    file_ids = []

    for fname in new_files:
        # Skip if already in project
        basename = fname.split("/")[-1]
        if basename in content:
            print(f"  SKIP (already present): {fname}")
            continue

        bid = gen_id()
        fid = gen_id()
        build_ids.append((bid, fid, fname))
        file_ids.append((fid, fname))

    if not build_ids:
        print("All files already in project.")
        return

    # 1. PBXBuildFile entries
    marker = "/* End PBXBuildFile section */"
    entries = "\n".join(
        f'\t\t{bid} /* {fn} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fn} */; }};'
        for bid, fid, fn in build_ids
    )
    content = content.replace(marker, entries + "\n" + marker)

    # 2. PBXFileReference entries
    marker = "/* End PBXFileReference section */"
    entries = "\n".join(
        f'\t\t{fid} /* {fn} */ = {{isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = {fn}; sourceTree = "<group>"; }};'
        for fid, fn in file_ids
    )
    content = content.replace(marker, entries + "\n" + marker)

    # 3. Add to children of the DoseTap group
    # Find the group that contains ContentView.swift
    # We'll add file refs near ContentView.swift's reference in children
    for fid, fn in file_ids:
        basename = fn.split("/")[-1]
        # For Views/ files, find the Views group children
        if fn.startswith("Views/"):
            # Find existing Views file reference to locate the Views group
            view_pattern = r'(/\* Views \*/ = \{[^}]*children = \()([^)]*?)(\))'
            match = re.search(view_pattern, content, re.DOTALL)
            if match:
                insertion = match.group(2) + f"\n\t\t\t\t{fid} /* {basename} */,"
                content = content[:match.start(2)] + insertion + content[match.end(2):]
            else:
                # Fallback: find any children list that contains other Views/*.swift files
                # Look for a children block containing DiagnosticExportView.swift
                diag_pattern = r'(children = \([^)]*DiagnosticExportView\.swift[^)]*?)(\))'
                match2 = re.search(diag_pattern, content, re.DOTALL)
                if match2:
                    insertion = match2.group(1) + f"\n\t\t\t\t{fid} /* {basename} */,"
                    content = content[:match2.start(1)] + insertion + content[match2.end(1):]
        else:
            # Root-level file: add near ContentView.swift in the main DoseTap group
            cv_pattern = r'(B02 /\* ContentView\.swift \*/,)'
            content = re.sub(
                cv_pattern,
                f'\\1\n\t\t\t\t{fid} /* {basename} */,',
                content
            )

    # 4. Add to PBXSourcesBuildPhase
    # Find the sources build phase for the app target
    sources_pattern = r'(/\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = [^;]*;\s*files = \()([^)]*?)(\))'
    match = re.search(sources_pattern, content, re.DOTALL)
    if match:
        existing = match.group(2)
        new_entries = "\n".join(
            f'\t\t\t\t{bid} /* {fn} in Sources */,'
            for bid, fid, fn in build_ids
        )
        content = content[:match.start(2)] + existing + "\n" + new_entries + content[match.end(2):]

    with open(PROJ, "w") as f:
        f.write(content)

    print(f"Added {len(build_ids)} files to Xcode project:")
    for _, _, fn in build_ids:
        print(f"  + {fn}")

if __name__ == "__main__":
    main()
