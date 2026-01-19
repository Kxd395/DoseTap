from __future__ import annotations

import sqlite3
from pathlib import Path

from sidecar_ledger.commands.init import init_cmd
from sidecar_ledger.commands.ingest import ingest_cmd


class Args:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


def test_init_and_ingest(tmp_path: Path):
    root = tmp_path / "pipeline"
    root.mkdir()

    # init
    init_cmd(Args(root=str(root), force=False))
    db = root / "_ledger" / "ledger.sqlite"
    assert db.exists()

    # seed inbox
    inbox = root / "00_Inbox"
    inbox.mkdir(exist_ok=True)
    (inbox / "a.txt").write_text("hello", encoding="utf-8")

    ingest_cmd(Args(root=str(root), source="TEST", dry_run=False))

    with sqlite3.connect(str(db)) as conn:
        media_count = conn.execute("SELECT COUNT(*) FROM media_item").fetchone()[0]
        ver_count = conn.execute("SELECT COUNT(*) FROM verification_event").fetchone()[0]
    assert media_count == 1
    assert ver_count == 1
