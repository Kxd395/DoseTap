# SidecarLedger TODO

## Phase 0: Scaffold (this repo)

- [x] Folder structure script
- [x] Ledger schema
- [x] Minimal Python CLI (`init`, `ingest`)
- [ ] `docs/PIPELINE_SSOT.md` invariants + state machine (tighten as implementation lands)

## Phase 1: Ingest

- [x] Hash file SHA-256
- [x] Copy from `00_Inbox` -> `01_Staging`
- [ ] Optional: detect duplicates by hash before copying
- [ ] Optional: mime sniffing (vs extension)

## Phase 2: Sidecar generation

- [ ] `sidecar` command using `exiftool -o %d%f.xmp -tagsFromFile @ -all:all` (or chosen pattern)
- [ ] Record `sidecar_path` + `sidecar_sha256`
- [ ] Status transition STAGED -> WORKING

## Phase 3: Rules + review gate

- [ ] Validate required fields in XMP (e.g. `dc:description`, `xmp:CreateDate`)
- [ ] Generate `_reports/review.md`
- [ ] READY_FOR_REVIEW vs QUARANTINED

## Phase 4: Commit

- [ ] Commit into `03_Archive/YYYY/MM`
- [ ] Commit event hash chaining

## Phase 5: Audit + rollback

- [ ] Audit drift (rehash file + sidecar)
- [ ] Rollback from commit chain
