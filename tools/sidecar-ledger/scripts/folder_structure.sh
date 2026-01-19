#!/usr/bin/env bash
set -euo pipefail

# SidecarLedger scaffold
# Creates a deterministic folder layout for a pipeline root.

ROOT="${1:-.}"

mkdir -p "$ROOT"

mkdir -p "$ROOT/00_Inbox"
mkdir -p "$ROOT/01_Staging"
mkdir -p "$ROOT/02_Working"
mkdir -p "$ROOT/03_Archive/.keep"
mkdir -p "$ROOT/04_Exports"
mkdir -p "$ROOT/90_Quarantine"

mkdir -p "$ROOT/_ledger"
mkdir -p "$ROOT/_logs"
mkdir -p "$ROOT/_reports"
mkdir -p "$ROOT/_tmp"

mkdir -p "$ROOT/docs"
mkdir -p "$ROOT/docs/archives"

cat > "$ROOT/.gitignore" <<'EOF'
_ledger/
_logs/
_tmp/
04_Exports/
.DS_Store
EOF

echo "Pipeline root created at: $ROOT"
echo "Next: python3 -m sidecar_ledger init --root '$ROOT'"
