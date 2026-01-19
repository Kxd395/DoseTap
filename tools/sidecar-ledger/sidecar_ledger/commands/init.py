from __future__ import annotations

import argparse
from pathlib import Path

from sidecar_ledger.core.ledger import Ledger
from sidecar_ledger.core.paths import PipelinePaths
from sidecar_ledger.core.util import ensure_dir


def init_cmd(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser().resolve()
    paths = PipelinePaths(root)

    # Ensure minimal directories in case user didn't run the shell scaffold.
    for d in [
        paths.ledger_dir,
        paths.logs_dir,
        paths.reports_dir,
        paths.inbox_dir,
        paths.staging_dir,
        paths.working_dir,
        paths.archive_dir,
        paths.quarantine_dir,
    ]:
        ensure_dir(d)

    ledger = Ledger(paths.ledger_db)
    ledger.initialize(schema_path=paths.schema_path)
    print(f"Initialized ledger at {paths.ledger_db}")
    return 0
