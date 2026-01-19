from __future__ import annotations

import argparse

from sidecar_ledger.commands.ingest import ingest_cmd
from sidecar_ledger.commands.init import init_cmd


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="sidecar_ledger")
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init", help="Initialize pipeline root ledger")
    p_init.add_argument("--root", required=True, help="Pipeline root path")
    p_init.add_argument(
        "--force",
        action="store_true",
        help="Recreate ledger tables (idempotent schema apply) even if db exists",
    )
    p_init.set_defaults(func=init_cmd)

    p_ingest = sub.add_parser("ingest", help="Ingest files from 00_Inbox into 01_Staging")
    p_ingest.add_argument("--root", required=True, help="Pipeline root path")
    p_ingest.add_argument(
        "--source",
        required=True,
        help='Logical source label, e.g. "SD_CARD", "iPhone", "Scan", "MANUAL"',
    )
    p_ingest.add_argument("--dry-run", action="store_true", help="Plan actions without writing")
    p_ingest.set_defaults(func=ingest_cmd)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))
