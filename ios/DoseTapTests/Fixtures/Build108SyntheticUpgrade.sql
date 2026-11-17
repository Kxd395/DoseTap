-- Synthetic upgrade database from DoseTap 0.4.19 (108), source commit 666e259.
-- The original fixture, SHA-256 dc493bd589e88f715c6cb96c7ce6dbfaccd1b2ac3279563476840b379624a2f6,
-- was created through its storage APIs. The same build added a correction to the
-- zero check-in and saved a prompt schedule, work roster, dashboard review and
-- synthetic provider association. The SQL dump retains all original table rows and
-- indexes and allows review without bundling a device database.
BEGIN TRANSACTION;
CREATE TABLE body_map_points (
    id TEXT PRIMARY KEY,
    location_id TEXT NOT NULL,
    map_id TEXT NOT NULL,
    normalized_x REAL NOT NULL CHECK (normalized_x >= 0.0 AND normalized_x <= 1.0),
    normalized_y REAL NOT NULL CHECK (normalized_y >= 0.0 AND normalized_y <= 1.0),
    zoom_level REAL NOT NULL DEFAULT 1.0 CHECK (zoom_level > 0.0),
    body_view TEXT NOT NULL,
    FOREIGN KEY(location_id) REFERENCES symptom_locations(id) ON DELETE CASCADE
);
CREATE TABLE checkin_submissions (
    id TEXT PRIMARY KEY,
    source_record_id TEXT NOT NULL,
    session_id TEXT,
    session_date TEXT NOT NULL,
    checkin_type TEXT NOT NULL,
    questionnaire_version TEXT NOT NULL,
    user_id TEXT NOT NULL,
    submitted_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL,
    responses_json TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(source_record_id, checkin_type)
);
CREATE TABLE cloudkit_tombstones (
    key TEXT PRIMARY KEY,
    record_type TEXT NOT NULL,
    record_name TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE confirmed_medication_administrations (
    id TEXT PRIMARY KEY, revision_id TEXT NOT NULL REFERENCES medication_preset_revisions(id),
    recorded_at_utc TEXT NOT NULL, occurred_at_utc TEXT, payload TEXT NOT NULL
);
CREATE TABLE current_session (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    dose1_time TEXT,
    dose2_time TEXT,
    snooze_count INTEGER DEFAULT 0,
    dose2_skipped INTEGER DEFAULT 0,
    session_date TEXT NOT NULL,
    session_id TEXT,
    session_start_utc TEXT,
    session_end_utc TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
, terminal_state TEXT);
INSERT INTO "current_session" VALUES(1,'2026-09-21T14:13:20.000Z',NULL,0,0,'2026-09-20','5D0A8258-0F89-4B83-BA61-85F736B4DDB0','2026-09-21T14:13:20.000Z',NULL,'2026-11-17 20:10:08',NULL);
CREATE TABLE dashboard_dose_reviews (
    observation_id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    payload TEXT NOT NULL
);
INSERT INTO "dashboard_dose_reviews" VALUES('session:synthetic-review','2026-09-30','{"revisions":[{"revisionID":"DD536BBE-9471-4BCB-9A9B-C21852EFBBE7","observationID":"session:synthetic-review","confirmedCount":1,"recordedAt":811692800,"version":1,"reason":"Synthetic","sourceFingerprint":"evidence"}]}');
CREATE TABLE dashboard_provider_associations (
    episode_id TEXT PRIMARY KEY, provider TEXT NOT NULL, session_id TEXT NOT NULL,
    session_date TEXT NOT NULL, session_fingerprint TEXT NOT NULL, episode_fingerprint TEXT NOT NULL,
    revision TEXT NOT NULL, recorded_at TEXT NOT NULL, UNIQUE(provider, session_id)
);
INSERT INTO "dashboard_provider_associations" VALUES('apple-health:synthetic-episode','apple-health','5D0A8258-0F89-4B83-BA61-85F736B4DDB0','2026-09-20','4d508b28caa76645946efec24119f67ad7af1839b2520a1b8e51ba674a594b57','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','195D08B9-4738-402A-8C6A-9FB5FD1C901E','2026-09-21T14:13:20.000Z');
CREATE TABLE daytime_checkins (
    revision_id TEXT PRIMARY KEY, observation_id TEXT NOT NULL, payload TEXT NOT NULL
);
INSERT INTO "daytime_checkins" VALUES('0FF5F5C9-9733-4072-9DDB-29C7A6E17D17','4558EB0B-04D3-496E-8548-27C91DFE6195','{"assessedAt":1790000000,"contentVersion":"custom-0-10-v1","coping":"Not answered","copingActions":[],"createdAt":1790000000,"id":"4558EB0B-04D3-496E-8548-27C91DFE6195","instrumentID":"dosetap.custom-current-sleepiness","language":"en","note":"","origin":"userInitiated","recordedAt":1790000000,"response":0,"revisionID":"0FF5F5C9-9733-4072-9DDB-29C7A6E17D17","setting":"Not answered","status":"answered","timeZoneIdentifier":"UTC","utcOffsetSeconds":0}');
INSERT INTO "daytime_checkins" VALUES('754DC874-998B-440F-A093-24328DDDC735','4558EB0B-04D3-496E-8548-27C91DFE6195','{"assessedAt":1790000000,"contentVersion":"custom-0-10-v1","coping":"Not answered","copingActions":[],"correctionReason":"Synthetic revision","createdAt":1790000000,"id":"4558EB0B-04D3-496E-8548-27C91DFE6195","instrumentID":"dosetap.custom-current-sleepiness","language":"en","note":"","origin":"userInitiated","predecessorID":"0FF5F5C9-9733-4072-9DDB-29C7A6E17D17","recordedAt":1790000030,"revisionID":"754DC874-998B-440F-A093-24328DDDC735","setting":"Not answered","status":"unsure","timeZoneIdentifier":"UTC","utcOffsetSeconds":0}');
CREATE TABLE daytime_events (
    revision_id TEXT PRIMARY KEY, event_id TEXT NOT NULL, payload TEXT NOT NULL
);
INSERT INTO "daytime_events" VALUES('8F218F20-BF66-46C5-B3F0-7038A18F4F38','2C4C9E61-0F4D-4033-BBF0-7CAD995CD90F','{"createdAt":1790000000,"id":"2C4C9E61-0F4D-4033-BBF0-7CAD995CD90F","kind":"Unplanned sleep","note":"","occurredAt":1790000000,"precision":"Approximate time","recordedAt":1790000000,"revisionID":"8F218F20-BF66-46C5-B3F0-7038A18F4F38","timeZoneIdentifier":"UTC","version":1}');
CREATE TABLE daytime_prompt_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    payload TEXT NOT NULL
);
INSERT INTO "daytime_prompt_state" VALUES(1,'{"enabled":true,"prompts":[],"quietEnd":420,"quietStart":1320,"schedules":[{"createdAt":"2026-09-21T14:13:20.000Z","hour":14,"id":"E932413E-375A-4B14-8716-8530CAA2F2EE","minute":0,"timeZone":"UTC"}]}');
CREATE TABLE dose_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,
    session_id TEXT,
    metadata TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
, is_hazard INTEGER DEFAULT 0);
INSERT INTO "dose_events" VALUES('D3499911-CCA6-4C58-952B-2A611C88871E','dose1','2026-09-21T14:13:20.000Z','2026-09-20','5D0A8258-0F89-4B83-BA61-85F736B4DDB0',NULL,'2026-11-17 20:10:08',0);
CREATE TABLE inventory_snapshots (
    id TEXT PRIMARY KEY,
    as_of_utc TEXT NOT NULL,
    medication_name TEXT NOT NULL,
    bottles_remaining INTEGER NOT NULL DEFAULT 0 CHECK (bottles_remaining >= 0),
    doses_remaining INTEGER NOT NULL DEFAULT 0 CHECK (doses_remaining >= 0),
    estimated_days_left INTEGER,
    next_refill_date TEXT,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE medication_events (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    session_date TEXT NOT NULL,
    medication_id TEXT NOT NULL,
    dose_mg INTEGER NOT NULL,
    dose_unit TEXT NOT NULL DEFAULT 'mg',
    formulation TEXT NOT NULL DEFAULT 'ir',
    taken_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    confirmed_duplicate INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE medication_preset_revisions (
    id TEXT PRIMARY KEY, preset_id TEXT NOT NULL, predecessor_id TEXT,
    recorded_at_utc TEXT NOT NULL, payload TEXT NOT NULL
);
CREATE TABLE morning_checkins (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,

    -- Core sleep assessment (always captured)
    sleep_quality REAL NOT NULL DEFAULT 3,
    feel_rested TEXT NOT NULL DEFAULT 'moderate',
    grogginess TEXT NOT NULL DEFAULT 'mild',
    sleep_inertia_duration TEXT NOT NULL DEFAULT 'fiveToFifteen',
    dream_recall TEXT NOT NULL DEFAULT 'none',

    -- Physical symptoms (optional - JSON blob for flexibility, includes painNotes)
    has_physical_symptoms INTEGER NOT NULL DEFAULT 0,
    physical_symptoms_json TEXT,

    -- Respiratory symptoms (optional - JSON blob, includes respiratoryNotes)
    has_respiratory_symptoms INTEGER NOT NULL DEFAULT 0,
    respiratory_symptoms_json TEXT,

    -- Mental state (always captured)
    mental_clarity INTEGER NOT NULL DEFAULT 5,
    mood TEXT NOT NULL DEFAULT 'neutral',
    anxiety_level TEXT NOT NULL DEFAULT 'none',
    stress_level INTEGER,
    stress_context_json TEXT,
    readiness_for_day INTEGER NOT NULL DEFAULT 3,

    -- Narcolepsy-specific flags
    had_sleep_paralysis INTEGER NOT NULL DEFAULT 0,
    had_hallucinations INTEGER NOT NULL DEFAULT 0,
    had_automatic_behavior INTEGER NOT NULL DEFAULT 0,
    fell_out_of_bed INTEGER NOT NULL DEFAULT 0,
    had_confusion_on_waking INTEGER NOT NULL DEFAULT 0,

    -- Sleep Therapy Device (NEW)
    used_sleep_therapy INTEGER NOT NULL DEFAULT 0,
    sleep_therapy_json TEXT,
    timing_context_json TEXT,

    -- Notes
    notes TEXT,

    created_at TEXT DEFAULT CURRENT_TIMESTAMP
, has_sleep_environment INTEGER NOT NULL DEFAULT 0, sleep_environment_json TEXT);
CREATE TABLE nap_diary (
    id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL
);
INSERT INTO "nap_diary" VALUES(1,'{"episodes":[{"timeZoneID":"UTC","id":"synthetic-nap","intent":"Not answered","reason":"","day":"2026-09-21","end":811692800,"recordedAt":811692800,"sourceEventIDs":[],"revision":"2D412C33-0ED4-4CF9-973B-0825CE090E99","start":811689200,"estimatedSleepMinutes":20}],"version":1,"revision":"7D611BBD-7BE0-443B-817E-7265999AF15E","reviews":[]}');
CREATE TABLE physician_review_records (
    id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK (kind IN ('visit', 'report')), payload TEXT NOT NULL
);
INSERT INTO "physician_review_records" VALUES('31D8ECF4-A164-4C1D-ACE1-07169713057D','visit','{"id":"E6B904C0-6303-4F6D-B431-C6689B877F03","note":"","occurredAt":811606400,"recordedAt":811692800,"revisionID":"31D8ECF4-A164-4C1D-ACE1-07169713057D"}');
CREATE TABLE pre_sleep_logs (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    created_at_utc TEXT NOT NULL,
    local_offset_minutes INTEGER NOT NULL,
    completion_state TEXT NOT NULL DEFAULT 'partial',
    answers_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE schema_migrations (
    id TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "schema_migrations" VALUES('event_types_normalized_v1','2026-11-17T20:10:08.022Z');
INSERT INTO "schema_migrations" VALUES('brief_wake_alias_migration_v1','2026-11-17T20:10:08.023Z');
INSERT INTO "schema_migrations" VALUES('session_id_uuid_migration_v1','2026-11-17T20:10:08.023Z');
INSERT INTO "schema_migrations" VALUES('event_deduplication_v1','2026-11-17T20:10:08.023Z');
CREATE TABLE sleep_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    session_date TEXT NOT NULL,
    session_id TEXT,
    color_hex TEXT,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE sleep_sessions (
    session_id TEXT PRIMARY KEY,
    session_date TEXT NOT NULL,
    start_utc TEXT NOT NULL,
    end_utc TEXT,
    terminal_state TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "sleep_sessions" VALUES('5D0A8258-0F89-4B83-BA61-85F736B4DDB0','2026-09-20','2026-09-21T14:13:20.000Z',NULL,NULL,'2026-11-17 20:10:08','2026-11-17 20:10:08');
CREATE TABLE supply_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    payload TEXT NOT NULL
);
CREATE TABLE symptom_command_log (
    idempotency_key TEXT PRIMARY KEY,
    command_type TEXT NOT NULL,
    source TEXT NOT NULL,
    source_record_id TEXT,
    source_entry_key TEXT,
    session_id TEXT,
    session_date TEXT,
    status TEXT NOT NULL,
    created_event_id TEXT,
    error_code TEXT,
    created_at TEXT NOT NULL,
    completed_at TEXT
);
CREATE TABLE symptom_events (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    session_date TEXT NOT NULL,
    phase TEXT NOT NULL,
    source TEXT NOT NULL,
    source_record_id TEXT,
    source_entry_key TEXT,
    kind TEXT NOT NULL,
    noticed_at TEXT NOT NULL,
    severity_0_10 INTEGER CHECK (severity_0_10 IS NULL OR severity_0_10 BETWEEN 0 AND 10),
    sleep_disruption INTEGER NOT NULL DEFAULT 0 CHECK (sleep_disruption IN (0, 1)),
    still_present INTEGER NOT NULL DEFAULT 0 CHECK (still_present IN (0, 1)),
    functional_impact TEXT,
    note TEXT,
    schema_version INTEGER NOT NULL DEFAULT 1,
    app_version TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE symptom_locations (
    id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL,
    body_side TEXT NOT NULL,
    body_region_id TEXT NOT NULL,
    anatomy_layer TEXT NOT NULL,
    precision TEXT NOT NULL,
    confidence TEXT NOT NULL,
    FOREIGN KEY(event_id) REFERENCES symptom_events(id) ON DELETE CASCADE
);
CREATE TABLE symptom_summaries (
    session_date TEXT PRIMARY KEY,
    session_id TEXT,
    symptom_count INTEGER NOT NULL,
    highest_severity INTEGER,
    sleep_disruption_count INTEGER NOT NULL,
    still_present_count INTEGER NOT NULL,
    summary_hash TEXT NOT NULL,
    rebuilt_at TEXT NOT NULL
);
CREATE TABLE work_block_context (
    id INTEGER PRIMARY KEY CHECK (id = 1), payload TEXT NOT NULL
);
INSERT INTO "work_block_context" VALUES(1,'{"schemaVersion":1,"revision":"0C28751F-6DE2-47A8-92BF-CFAB259537B4","rosters":[{"recordedAt":811692800,"effectiveFrom":"2026-09-01","id":"586F45DA-011E-4050-BF16-568C4DCF406B","effectiveTo":"2026-12-31","weekdays":[4,5,3],"timeZoneIdentifier":"UTC"}],"associations":[],"occurrences":[]}');
CREATE TABLE work_wake_schedule (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    payload TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_daytime_event ON daytime_events(event_id);
CREATE INDEX idx_daytime_observation ON daytime_checkins(observation_id);
CREATE INDEX idx_preset_revision_owner ON medication_preset_revisions(preset_id);
CREATE INDEX idx_confirmed_medication_recorded ON confirmed_medication_administrations(recorded_at_utc);
CREATE INDEX idx_sleep_events_session ON sleep_events(session_date);
CREATE INDEX idx_sleep_events_timestamp ON sleep_events(timestamp);
CREATE INDEX idx_sleep_events_session_type ON sleep_events(session_date, event_type);
CREATE INDEX idx_sleep_events_session_id ON sleep_events(session_id);
CREATE INDEX idx_dose_events_session ON dose_events(session_date);
CREATE INDEX idx_dose_events_session_type ON dose_events(session_date, event_type);
CREATE INDEX idx_dose_events_session_id ON dose_events(session_id);
CREATE INDEX idx_morning_checkins_session ON morning_checkins(session_date);
CREATE INDEX idx_morning_checkins_session_id ON morning_checkins(session_id);
CREATE INDEX idx_checkin_submissions_session_date ON checkin_submissions(session_date);
CREATE INDEX idx_checkin_submissions_session_id ON checkin_submissions(session_id);
CREATE INDEX idx_checkin_submissions_type_time ON checkin_submissions(checkin_type, submitted_at_utc);
CREATE INDEX idx_pre_sleep_logs_session_id ON pre_sleep_logs(session_id);
CREATE INDEX idx_sleep_sessions_date ON sleep_sessions(session_date);
CREATE INDEX idx_cloudkit_tombstones_created ON cloudkit_tombstones(created_at);
CREATE INDEX idx_medication_events_session ON medication_events(session_id);
CREATE INDEX idx_medication_events_session_date ON medication_events(session_date);
CREATE INDEX idx_medication_events_medication ON medication_events(medication_id);
CREATE INDEX idx_medication_events_taken_at ON medication_events(taken_at_utc);
CREATE INDEX idx_inventory_snapshots_as_of ON inventory_snapshots(as_of_utc);
CREATE INDEX idx_inventory_snapshots_medication ON inventory_snapshots(medication_name);
CREATE INDEX idx_symptom_events_session_date ON symptom_events(session_date);
CREATE INDEX idx_symptom_events_session_id ON symptom_events(session_id);
CREATE INDEX idx_symptom_events_phase_kind ON symptom_events(phase, kind);
CREATE INDEX idx_symptom_events_source_record ON symptom_events(source, source_record_id);
CREATE INDEX idx_symptom_locations_event ON symptom_locations(event_id);
CREATE INDEX idx_body_map_points_location ON body_map_points(location_id);
CREATE INDEX idx_symptom_command_log_status ON symptom_command_log(status);
CREATE INDEX idx_symptom_command_log_source_record ON symptom_command_log(source, source_record_id);
COMMIT;
PRAGMA user_version = 5;
