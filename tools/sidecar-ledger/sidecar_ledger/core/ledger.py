from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Optional


class Ledger:
    def __init__(self, db_path: Path):
        self.db_path = db_path

    def connect(self) -> sqlite3.Connection:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON;")
        return conn

    def initialize(self, *, schema_path: Path) -> None:
        sql = schema_path.read_text(encoding="utf-8")
        with self.connect() as conn:
            conn.executescript(sql)

    def insert_media_item(
        self,
        *,
        original_filename: str,
        original_source: str,
        original_path: str,
        ingest_utc: str,
        ingest_local: str,
        file_ext: str,
        mime_type: str,
        file_sha256: str,
        current_path: str,
        status: str,
        notes: Optional[str] = None,
    ) -> int:
        with self.connect() as conn:
            cur = conn.execute(
                """
                INSERT OR IGNORE INTO media_item (
                  original_filename,
                  original_source,
                  original_path,
                  ingest_utc,
                  ingest_local,
                  file_ext,
                  mime_type,
                  file_sha256,
                  current_path,
                  status,
                  notes
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    original_filename,
                    original_source,
                    original_path,
                    ingest_utc,
                    ingest_local,
                    file_ext,
                    mime_type,
                    file_sha256,
                    current_path,
                    status,
                    notes,
                ),
            )
            return int(cur.lastrowid or 0)

    def _media_item_id_for_sha(self, conn: sqlite3.Connection, *, file_sha256: str) -> int:
        row = conn.execute(
            "SELECT id FROM media_item WHERE file_sha256 = ?",
            (file_sha256,),
        ).fetchone()
        if not row:
            raise ValueError(f"media_item not found for sha256={file_sha256}")
        return int(row["id"])

    def insert_verification_event(
        self,
        *,
        media_file_sha256: str,
        verified_utc: str,
        verifier: str,
        kind: str,
        result: str,
        detail: Optional[str],
    ) -> int:
        with self.connect() as conn:
            media_id = self._media_item_id_for_sha(conn, file_sha256=media_file_sha256)
            cur = conn.execute(
                """
                INSERT INTO verification_event (
                  media_item_id,
                  verified_utc,
                  verifier,
                  kind,
                  result,
                  detail
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (media_id, verified_utc, verifier, kind, result, detail),
            )
            return int(cur.lastrowid)
