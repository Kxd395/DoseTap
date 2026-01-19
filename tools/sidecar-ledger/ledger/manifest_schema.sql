PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS media_item (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,

  original_filename  TEXT    NOT NULL,
  original_source    TEXT    NOT NULL,
  original_path      TEXT    NOT NULL,

  ingest_utc         TEXT    NOT NULL,
  ingest_local       TEXT    NOT NULL,

  file_ext           TEXT    NOT NULL,
  mime_type          TEXT    NOT NULL,

  file_sha256        TEXT    NOT NULL,
  pixel_sha256       TEXT    NULL,

  current_path       TEXT    NOT NULL,
  working_path       TEXT    NULL,
  archive_path       TEXT    NULL,

  sidecar_path       TEXT    NULL,
  sidecar_sha256     TEXT    NULL,

  status             TEXT    NOT NULL DEFAULT 'INGESTED',
  notes              TEXT    NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_media_item_file_sha256
ON media_item(file_sha256);

CREATE INDEX IF NOT EXISTS idx_media_item_status
ON media_item(status);

CREATE INDEX IF NOT EXISTS idx_media_item_ingest_utc
ON media_item(ingest_utc);

CREATE TABLE IF NOT EXISTS verification_event (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  media_item_id    INTEGER NOT NULL REFERENCES media_item(id) ON DELETE CASCADE,

  verified_utc     TEXT    NOT NULL,
  verifier         TEXT    NOT NULL,
  kind             TEXT    NOT NULL,
  result           TEXT    NOT NULL,
  detail           TEXT    NULL
);

CREATE INDEX IF NOT EXISTS idx_verification_event_media_item_id
ON verification_event(media_item_id);

CREATE INDEX IF NOT EXISTS idx_verification_event_verified_utc
ON verification_event(verified_utc);

CREATE TABLE IF NOT EXISTS commit_event (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  media_item_id    INTEGER NOT NULL REFERENCES media_item(id) ON DELETE CASCADE,

  commit_utc       TEXT    NOT NULL,
  committer        TEXT    NOT NULL,
  from_path        TEXT    NOT NULL,
  to_path          TEXT    NOT NULL,

  commit_hash      TEXT    NOT NULL,
  detail           TEXT    NULL
);

CREATE INDEX IF NOT EXISTS idx_commit_event_media_item_id
ON commit_event(media_item_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_commit_event_commit_hash
ON commit_event(commit_hash);

CREATE TABLE IF NOT EXISTS process_run (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  run_utc       TEXT    NOT NULL,
  tool          TEXT    NOT NULL,
  version       TEXT    NULL,
  args          TEXT    NULL,
  result        TEXT    NOT NULL,
  log_path      TEXT    NULL
);

CREATE INDEX IF NOT EXISTS idx_process_run_run_utc
ON process_run(run_utc);
