# Support Bundle Contract

## Overview
Privacy-focused diagnostic data export system for troubleshooting and technical support. PII (Personally Identifiable Information) is minimized through automatic redaction, with required user review before sharing.

**Privacy Posture**: PII-minimized (not guaranteed zero-PII), with automatic redaction of known sensitive fields plus mandatory user review step before export is shared.

## Bundle Contents

### Core Files
All support bundles include these standardized files:

**events.csv**
- Complete event history using existing CSV v1 schema
- Timestamps converted to relative offsets (e.g., "T+0:00", "T+2:45") 
- Personal notes field stripped or redacted
- Maintains event relationships and timing patterns

**inventory.csv** (if inventory feature enabled)
- Current inventory state using inventory CSV v1 schema
- Medication names generalized (e.g., "MEDICATION_A")
- Pharmacy information redacted
- Prescription numbers hashed

**app_metadata.json**
- App version and build number
- iOS version and device model
- Device timezone and locale
- Setup wizard completion status
- Feature enablement flags (notifications, iCloud sync, etc.)

**debug_log.txt**
- Application logs from past 7 days
- Error messages and stack traces
- Performance metrics and timing data
- Network connectivity status
- Notification delivery status

### Privacy Protection

**Automatic Redaction:**
- All timestamps converted to relative format
- Personal notes and pharmacy information removed
- Device identifiers hashed with session-specific salt
- User-entered text fields sanitized

**Excluded Data:**
- Raw HealthKit data (only aggregated metrics included)
- WHOOP authentication tokens
- iCloud account information
- Actual medication names (generalized to types)
- Specific dosage amounts (normalized to ratios)

## Export Process

### User Interface Flow
**Settings → Support & Diagnostics → Export Support Bundle**

**Step 1: Privacy Confirmation**
```
┌──────────────────────────────────────────────────────────────────────┐
│  Export Support Bundle                                               │
│                                                                      │
│  This creates a privacy-safe diagnostic file containing:             │
│  • Event timing patterns (no personal notes)                        │
│  • App performance data                                             │
│  • Error logs and crash reports                                     │
│                                                                      │
│  Personal information is automatically removed.                      │
│                                                                      │
│  [ Review Contents ]     [ Export Bundle ]                          │
│  VO: "Export Support Bundle. Personal information minimized."        │
└──────────────────────────────────────────────────────────────────────┘
```

**Step 1b: Review Contents (Required before first share)**
- Tapping "Review Contents" shows sample rows from each CSV
- User can see exactly what will be shared
- Any user-entered free-text fields highlighted for manual review
- User acknowledges: "I have reviewed this data and approve sharing"

**Step 2: Bundle Generation**
- Progress indicator during ZIP creation
- Estimated time: 2-5 seconds for typical dataset
- Background processing to maintain UI responsiveness

**Step 3: Share Options**
- iOS share sheet with bundle file
- Suggested actions: Mail, Files, AirDrop
- Include instructions text for support submission

### Share Instructions Template
```
Subject: DoseTap Support Bundle - [Brief Issue Description]

Please find attached diagnostic bundle for troubleshooting.

Issue Description: [User fills in]
Steps to Reproduce: [User fills in]
Expected vs Actual Behavior: [User fills in]

Technical Details:
- Support Bundle: [filename]
- Generated: [timestamp]
- App Version: [version from bundle]

Note: This bundle contains no personal information.
All timestamps and identifiers have been anonymized.
```

## Bundle Generation Logic

### File Assembly Process
1. **Create temporary directory** with session-specific name
2. **Export anonymized CSVs** using existing exporters with privacy filter
3. **Generate metadata JSON** with system information
4. **Extract debug logs** from past 7 days with PII filtering
5. **Create ZIP archive** with consistent internal structure
6. **Cleanup temporary files** after successful share

### Anonymization Engine
**Timestamp Conversion:**
- Establish earliest event as T+0:00:00
- Convert all timestamps to relative offsets
- Preserve time relationships and intervals
- Maintain timezone consistency

**Text Sanitization:**
- Remove or hash personal identifiers
- Replace medication names with generic types
- Redact contact information (phone, email)
- Preserve medically relevant keywords

**Data Generalization:**
- Normalize dosage amounts to standard ratios
- Round timing data to nearest 5-minute intervals
- Aggregate location-specific data (timezone regions)

## Bundle Structure

### ZIP Archive Layout
```
support_bundle_[timestamp].zip
├── README.txt (instructions and metadata)
├── events.csv (anonymized event history)
├── inventory.csv (generalized inventory data)
├── app_metadata.json (system information)
├── debug_log.txt (filtered application logs)
└── privacy_notice.txt (redaction summary)
```

### Metadata Schema
```json
{
  "bundle_version": "1.0",
  "generated_at": "2025-09-07T18:00:00Z",
  "app_version": "1.0.0",
  "app_build": "123",
  "ios_version": "17.2",
  "device_model": "iPhone15,2",
  "timezone": "America/New_York",
  "locale": "en_US",
  "setup_completed": true,
  "features_enabled": {
    "notifications": true,
    "icloud_sync": false,
    "health_integration": true,
    "inventory_tracking": true
  },
  "event_count": 47,
  "date_range_days": 30,
  "privacy_level": "high"
}
```

## Error Handling

### Bundle Generation Failures
**Insufficient Storage:**
- Check available disk space before generation
- Show specific error message with required space
- Offer to reduce bundle scope (fewer days of data)

**Export Permission Issues:**
- Handle share sheet cancellation gracefully
- Provide alternative export methods (Files app)
- Maintain bundle for retry attempts

**Data Corruption:**
- Validate CSV integrity before inclusion
- Skip corrupted files with notification
- Include validation report in bundle

### Privacy Validation
**Pre-Export Checks:**
- Scan all text fields for potential PII
- Verify timestamp anonymization accuracy
- Confirm no raw health data included
- Validate medication name generalization

**Post-Export Verification:**
- Optional bundle content review screen
- Sample of anonymized data for user verification
- Clear explanation of privacy protections applied

## Support Integration

### Technical Support Workflow
**Bundle Receipt:**
1. Automated validation of bundle format
2. Extraction and parsing of metadata
3. Event pattern analysis for common issues
4. Automated diagnostic report generation

**Common Issue Detection:**
- Notification delivery failures
- Timing calculation errors
- iCloud sync conflicts
- Health data integration problems
- Performance degradation patterns

### User Communication
**Status Updates:**
- Confirmation of bundle receipt
- Estimated resolution timeframe
- Request for additional information if needed
- Resolution notification with app update if applicable

## Testing Requirements

### Privacy Validation Tests
- Verify no PII in generated bundles across various user scenarios
- Test timestamp anonymization accuracy
- Validate text sanitization effectiveness
- Confirm medication name generalization

### Bundle Generation Tests
- Test with various data volumes (empty, small, large datasets)
- Verify ZIP archive integrity
- Test share sheet integration
- Validate metadata accuracy

### Error Scenario Tests
- Bundle generation with insufficient storage
- Corrupted source data handling
- Share cancellation and retry flows
- Network interruption during generation

## Compliance & Audit

### Privacy Documentation
- Bundle generation process documented for privacy review
- PII detection algorithms specified and tested
- Data retention policy for support bundles
- User consent and control mechanisms

### Audit Trail
- Log bundle generation events (without bundle contents)
- Track bundle sharing destinations for support purposes
- Monitor anonymization effectiveness
- Regular privacy impact assessments
