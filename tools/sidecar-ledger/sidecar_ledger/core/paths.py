from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class PipelinePaths:
    root: Path

    @property
    def inbox_dir(self) -> Path:
        return self.root / "00_Inbox"

    @property
    def staging_dir(self) -> Path:
        return self.root / "01_Staging"

    @property
    def working_dir(self) -> Path:
        return self.root / "02_Working"

    @property
    def archive_dir(self) -> Path:
        return self.root / "03_Archive"

    @property
    def quarantine_dir(self) -> Path:
        return self.root / "90_Quarantine"

    @property
    def ledger_dir(self) -> Path:
        return self.root / "_ledger"

    @property
    def ledger_db(self) -> Path:
        return self.ledger_dir / "ledger.sqlite"

    @property
    def logs_dir(self) -> Path:
        return self.root / "_logs"

    @property
    def reports_dir(self) -> Path:
        return self.root / "_reports"

    @property
    def schema_path(self) -> Path:
        # Allow running from inside repo. If not found, caller should provide explicit schema.
        return Path(__file__).resolve().parents[2] / "ledger" / "manifest_schema.sql"
