from __future__ import annotations

import argparse
import mimetypes
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from sidecar_ledger.core.hashing import sha256_file
from sidecar_ledger.core.ledger import Ledger
from sidecar_ledger.core.paths import PipelinePaths
from sidecar_ledger.core.util import iso_utc, iso_local


@dataclass(frozen=True)
class IngestPlanItem:
    src: Path
    dst: Path


def ingest_cmd(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser().resolve()
    paths = PipelinePaths(root)
    ledger = Ledger(paths.ledger_db)

    # Decide what to ingest
    inbox_files = sorted([p for p in paths.inbox_dir.iterdir() if p.is_file()])
    if not inbox_files:
        print("No files found in 00_Inbox")
        return 0

    plan: list[IngestPlanItem] = []
    for f in inbox_files:
        dst = paths.staging_dir / f.name
        plan.append(IngestPlanItem(src=f, dst=dst))

    if args.dry_run:
        for item in plan:
            print(f"DRY-RUN: would copy {item.src} -> {item.dst}")
        return 0

    now = datetime.now(timezone.utc)
    for item in plan:
        # Copy first, then hash the staged copy (so ledger matches staging)
        item.dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item.src, item.dst)

        file_sha = sha256_file(item.dst)
        ext = item.dst.suffix.lower().lstrip(".") or "(none)"
        mime, _ = mimetypes.guess_type(str(item.dst))
        mime = mime or "application/octet-stream"

        ledger.insert_media_item(
            original_filename=item.src.name,
            original_source=str(args.source),
            original_path=str(item.src),
            ingest_utc=iso_utc(now),
            ingest_local=iso_local(now),
            file_ext=ext,
            mime_type=mime,
            file_sha256=file_sha,
            current_path=str(item.dst),
            status="STAGED",
        )
        ledger.insert_verification_event(
            media_file_sha256=file_sha,
            verified_utc=iso_utc(now),
            verifier="ingest",
            kind="FILE_HASH",
            result="PASS",
            detail=None,
        )

        # Optional: remove from inbox after copy
        item.src.unlink()

    return 0
