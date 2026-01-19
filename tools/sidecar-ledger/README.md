# SidecarLedger

SidecarLedger is a local-first photo/video metadata pipeline built around a hard split of responsibilities:

* **XMP sidecars are the metadata source of truth** (human-editable, portable).
* **SQLite is the process source of truth** (hashes, locations, verification, audit trail).

This prevents “split brain”: the database never attempts to mirror your tags/descriptions.

## Layout

The pipeline root is a folder you generate with `scripts/folder_structure.sh`:

* `00_Inbox/` raw intake (camera card, phone dumps)
* `01_Staging/` validated copies ready for sidecar generation
* `02_Working/` metadata editing happens here (files + `.xmp`)
* `03_Archive/` committed storage by `YYYY/MM`
* `90_Quarantine/` failures
* `_ledger/` `ledger.sqlite` + schema/migrations
* `_logs/` tool logs
* `_reports/` generated review and audits

## Prereqs (macOS)

* `python3`
* `sqlite3`
* `exiftool` (only required for real sidecar generation)

## Quick start (local)

```bash
cd tools/sidecar-ledger

# 1) Create a new pipeline root folder anywhere you want
./scripts/folder_structure.sh /tmp/sidecar-ledger-demo

# 2) Initialize ledger DB
python3 -m sidecar_ledger init --root /tmp/sidecar-ledger-demo

# 3) Drop a file into Inbox
echo "hello" > /tmp/sidecar-ledger-demo/00_Inbox/demo.txt

# 4) Ingest to staging + write ledger row
python3 -m sidecar_ledger ingest --root /tmp/sidecar-ledger-demo --source MANUAL
```

## Next steps

* Implement `sidecar` command (exiftool-driven) to generate `.xmp` into `02_Working`.
* Implement rules + review gate.
* Implement commit and rollback.
