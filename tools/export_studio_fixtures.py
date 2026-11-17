#!/usr/bin/env python3
"""Extract the six synthetic iOS XCTest archives required by Studio CI."""
import argparse
import json
import re
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import zipfile

ARCHIVES = {
    "collected": "collected-night-roundtrip.zip",
    "raw-only": "raw-only-identity-roundtrip.zip",
    "medication": "stored-medication-roundtrip.zip",
    "events": "stored-events-roundtrip.zip",
    "whoop": "whoop-partial-recovery-roundtrip.zip",
    "health": "apple-health-biometrics-only-roundtrip.zip",
}
MAX_SIZE = 64 * 1024 * 1024


def extract(attachments: Path, output: Path) -> None:
    attachments = attachments.resolve(strict=True)
    manifest = json.loads((attachments / "manifest.json").read_text())
    if not isinstance(manifest, list):
        raise ValueError("Unsupported XCTest attachment manifest")
    if output.exists():
        raise ValueError("Refusing to overwrite an existing fixture directory")
    selected = {}
    for label, name in ARCHIVES.items():
        matches = [item for test in manifest for item in test.get("attachments", [])
                   if re.fullmatch(re.escape(Path(name).stem) + r"(?:_\d+_[0-9A-Fa-f-]{36})?\.zip",
                                   item.get("suggestedHumanReadableName", ""))]
        if len(matches) != 1:
            raise ValueError(f"Expected one {name} attachment; found {len(matches)}")
        candidate = (attachments / matches[0]["exportedFileName"]).resolve(strict=True)
        if not candidate.is_relative_to(attachments) or not candidate.is_file():
            raise ValueError(f"Invalid attachment path for {name}")
        selected[label] = candidate
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="studio-fixtures-", dir=output.parent))
    try:
        for label, archive in selected.items():
            with zipfile.ZipFile(archive) as source:
                members = source.infolist()
                if not members or len(members) > 1000 or sum(m.file_size for m in members) > MAX_SIZE:
                    raise ValueError(f"Invalid archive size for {label}")
                names = set()
                for member in members:
                    path = PurePosixPath(member.filename)
                    if (path.is_absolute() or ".." in path.parts or "\\" in member.filename
                            or member.filename in names or stat.S_ISLNK(member.external_attr >> 16)):
                        raise ValueError(f"Unsafe or duplicate archive member in {label}")
                    names.add(member.filename)
                destination = staging / label
                source.extractall(destination)
                bundles = list(destination.rglob("insights_bundle.json"))
                if len(bundles) != 1:
                    raise ValueError(f"Expected one insights bundle in {label}")
                root = bundles[0].parent
                if root != destination:
                    if root.parent != destination or list(destination.iterdir()) != [root]:
                        raise ValueError(f"Unexpected archive layout in {label}")
                    for child in list(root.iterdir()):
                        child.rename(destination / child.name)
                    root.rmdir()
                json.loads((destination / "insights_bundle.json").read_text())
        staging.rename(output)
    except BaseException:
        shutil.rmtree(staging)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("attachments", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        extract(args.attachments, args.output)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Fixture extraction failed: {error}\n")
    print(f"Prepared {len(ARCHIVES)} synthetic iOS export fixtures in {args.output}")


if __name__ == "__main__":
    main()
