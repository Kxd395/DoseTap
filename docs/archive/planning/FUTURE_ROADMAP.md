# DoseTap Future Roadmap

> **Vision**: Transform DoseTap from a dose timer into a comprehensive narcolepsy management companion that surfaces actionable insights through correlation analysis.

**Last Updated:** December 24, 2025

---

## Current State (v2.1)

- ✅ XYWAV dose timing (Dose 1 → 150-240m window → Dose 2)
- ✅ 13 sleep event types with rate limiting
- ✅ Basic WHOOP/HealthKit integration
- ✅ SQLite local-first storage
- ✅ watchOS companion with timer
- ✅ 207 unit tests

---

## Phase 3: Biometric Deep Integration

### 3.1 Apple Health Biometrics

| Metric | HealthKit Type | Correlation Value |
|--------|---------------|-------------------|
| **Heart Rate** | `HKQuantityTypeIdentifierHeartRate` | Wake events, anxiety episodes |
| **HRV** | `HKQuantityTypeIdentifierHeartRateVariabilitySDNN` | Recovery quality, sleep efficiency |
| **Blood Oxygen (SpO2)** | `HKQuantityTypeIdentifierOxygenSaturation` | Sleep apnea detection (common comorbidity) |
| **Respiratory Rate** | `HKQuantityTypeIdentifierRespiratoryRate` | Sleep stage correlation, disturbances |
| **Body Temperature** | `HKQuantityTypeIdentifierBodyTemperature` | Circadian rhythm marker |
| **Sleep Stages** | `HKCategoryTypeIdentifierSleepAnalysis` (watchOS 9+) | REM/Deep/Light distribution |
| **Wrist Temperature** | `HKQuantityTypeIdentifierAppleSleepingWristTemperature` | Cycle tracking, illness detection |

**Implementation:**
```swift
// New file: ios/Core/BiometricCorrelator.swift
public struct BiometricSnapshot {
    let timestamp: Date
    let heartRate: Double?
    let hrv: Double?
    let spo2: Double?
    let respiratoryRate: Double?
    let bodyTemp: Double?
    let sleepStage: SleepStage?
}

public actor BiometricCorrelator {
    func correlateWithEvent(_ event: SleepEvent, window: TimeInterval = 300) async -> BiometricSnapshot?
    func avgHRVForSession(_ sessionId: UUID) async -> Double?
    func detectAnomalies(for date: Date) async -> [BiometricAnomaly]
}
```

### 3.2 WHOOP Enhanced Metrics

- **Strain score** → Correlate with sleep quality
- **Recovery score** → Morning readiness predictor
- **Sleep performance** → Compare with DoseTap-logged events
- **HRV during sleep** → Higher resolution than Apple Watch

---

## Phase 4: Medication & Substance Tracking

### 4.1 Interfering Medications

**Critical for narcolepsy patients:**

| Medication | Category | Key Interaction |
|------------|----------|-----------------|
| **Adderall/Vyvanse** | Stimulant | Late doses (after 2pm) impair sleep onset |
| **Modafinil/Armodafinil** | Wakefulness | Half-life ~15h, timing critical |
| **Ritalin** | Stimulant | Shorter half-life, less evening impact |
| **Antidepressants** | SSRIs/SNRIs | Many affect REM sleep |
| **Xyrem (sodium oxybate)** | For users switching | Different formulation timing |

**Data Model:**
```swift
public struct MedicationDose: Codable, Identifiable {
    let id: UUID
    let medication: Medication
    let doseMg: Double
    let takenAt: Date
    let scheduledFor: Date?  // Track if taken late
    let notes: String?
}

public struct Medication: Codable {
    let name: String
    let category: MedicationCategory
    let halfLifeHours: Double?
    let interactsWith: [InteractionType]
}

public enum MedicationCategory: String, Codable {
    case stimulant
    case wakefulness
    case antidepressant
    case anxiolytic
    case sleepAid
    case other
}
```

**Insights to Generate:**
- "Adderall taken after 2pm correlates with 23min longer sleep onset"
- "Best nights occur when last stimulant is before 1pm"
- "Consider discussing dose timing with your provider"

### 4.2 Caffeine Tracking

- Time of last caffeine
- Total daily intake (mg)
- Correlate with sleep onset latency
- Smart cutoff reminder ("Last caffeine should be before 2pm for optimal sleep")

---

## Phase 5: Nutrition & Meal Timing

### 5.1 The XYWAV Meal Problem

**Critical constraint**: XYWAV must be taken ≥2 hours after eating for proper absorption.

**Data Model:**
```swift
public struct Meal: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let size: MealSize
    let fatContent: FatLevel
    let notes: String?
}

public enum MealSize: String, Codable, CaseIterable {
    case snack = "Snack"
    case light = "Light Meal"
    case moderate = "Moderate"
    case heavy = "Heavy Meal"
}

public enum FatLevel: String, Codable, CaseIterable {
    case low = "Low Fat"
    case moderate = "Moderate Fat"
    case high = "High Fat"  // Delays absorption most
}
```

**Smart Features:**
- "Last meal was 1h 45m ago. Wait 15 more minutes before Dose 1."
- "Heavy high-fat meals correlate with 18% more wake events"
- "Your best nights follow light dinners before 7pm"

### 5.2 Alcohol Warning

**XYWAV + alcohol is dangerous** (CNS depression risk)

- Track if alcohol consumed that day
- Show prominent warning if alcohol logged
- "Alcohol detected today. Consider skipping tonight's dose and consulting your provider."

---

## Phase 6: Sleep Quality Metrics

### 6.1 Derived Metrics

| Metric | Calculation | Target |
|--------|-------------|--------|
| **Sleep Onset Latency** | Time from Dose 1 to first sleep detected | <20 min |
| **Dose Interval** | Time between Dose 1 and Dose 2 | 150-240m (sweet spot ~165m) |
| **Wake Count** | Number of logged wake events | Lower is better |
| **Wake Duration** | Total time awake between doses | <15 min |
| **Sleep Efficiency** | (Total sleep / Time in bed) × 100 | >85% |
| **Morning Readiness** | Subjective rating + HRV | 1-10 scale |

### 6.2 Morning Check-in

### 6.2 Comprehensive Morning Check-in

A structured questionnaire designed to capture data valuable for sleep specialists. Designed to take ~60-90 seconds with smart defaults and skip logic.

#### Core Sleep Assessment

| Question | Input Type | Options |
|----------|------------|---------|
| **Overall sleep quality** | 5-star rating | ⭐ to ⭐⭐⭐⭐⭐ |
| **Do you feel rested?** | Scale | Not at all / Slightly / Moderately / Very / Completely |
| **Morning grogginess** | Select | None / Mild / Moderate / Severe / Can't function |
| **Sleep inertia duration** | Time picker | <5min / 5-15min / 15-30min / 30-60min / >1hr |
| **Dream recall** | Select | None / Vague / Normal / Vivid / Nightmares |

#### Physical Symptoms

| Category | Question | Input |
|----------|----------|-------|
| **Pain** | Any pain this morning? | Yes/No → If yes, expand |
| | Pain location | Multi-select: Head / Neck / Shoulders / Upper back / Lower back / Hips / Legs / Feet / Hands / Other |
| | Pain severity | 1-10 scale |
| | Pain type | Aching / Sharp / Stiff / Throbbing / Burning |
| **Headache** | Headache present? | None / Mild / Moderate / Severe / Migraine |
| | Headache location | Forehead / Temples / Back of head / Behind eyes / All over |
| **Muscle** | Muscle stiffness | None / Mild / Moderate / Severe |
| | Muscle soreness | None / Mild / Moderate / Severe |

#### Illness/Respiratory Symptoms

| Symptom | Options |
|---------|---------|
| **Congestion** | None / Stuffy nose / Runny nose / Both |
| **Throat** | Normal / Dry / Sore / Scratchy |
| **Cough** | None / Dry cough / Productive cough |
| **Sinus pressure** | None / Mild / Moderate / Severe |
| **Fever feeling** | No / Maybe / Yes |
| **General sick feeling** | No / Coming down with something / Actively sick / Recovering |

#### Mental/Cognitive State

| Question | Options |
|----------|---------|
| **Mental clarity** | Foggy / Somewhat clear / Clear / Very sharp |
| **Mood** | Low / Neutral / Good / Great |
| **Anxiety level** | None / Mild / Moderate / High |
| **Motivation** | None / Low / Normal / High |
| **Ready for day?** | Not at all / Need more time / Almost / Ready to go |

#### Narcolepsy-Specific Morning Questions

| Question | Purpose |
|----------|---------|
| **Sleep paralysis upon waking?** | Track hypnopompic symptoms |
| **Hallucinations upon waking?** | Track hypnopompic hallucinations |
| **Automatic behaviors during night?** | Doing things without awareness |
| **Fall out of bed?** | Can indicate REM behavior disorder |
| **Confusion upon waking?** | Sleep inertia severity indicator |

#### Quick Notes

- Free-text field for anything notable
- Voice-to-text option for quick entry
- "Anything to tell your doctor?" prompt

**Data Model:**

```swift
public struct MorningCheckin: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    
    // Core sleep
    let sleepQuality: Int  // 1-5
    let feelRested: RestedLevel
    let grogginess: SeverityLevel
    let sleepInertiaDuration: TimeInterval?
    let dreamRecall: DreamRecall
    
    // Pain
    let hasPain: Bool
    let painLocations: [PainLocation]?
    let painSeverity: Int?  // 1-10
    let painType: PainType?
    
    // Headache
    let headacheSeverity: SeverityLevel
    let headacheLocation: HeadacheLocation?
    
    // Respiratory/Illness
    let congestion: CongestionType
    let throatCondition: ThroatCondition
    let coughType: CoughType
    let sinusPressure: SeverityLevel
    let feelingSick: SicknessLevel
    
    // Mental state
    let mentalClarity: ClarityLevel
    let mood: MoodLevel
    let anxietyLevel: SeverityLevel
    let motivation: MotivationLevel
    let readyForDay: ReadinessLevel
    
    // Narcolepsy-specific
    let sleepParalysisOnWaking: Bool
    let hallucinationsOnWaking: Bool
    let automaticBehaviors: Bool
    let fellOutOfBed: Bool
    let confusionOnWaking: Bool
    
    // Notes
    let notes: String?
}

public enum PainLocation: String, Codable, CaseIterable {
    case head, neck, shoulders, upperBack, lowerBack
    case hips, legs, feet, hands, other
}

public enum SeverityLevel: String, Codable, CaseIterable {
    case none, mild, moderate, severe
}
```

**Smart Features:**

1. **Adaptive questionnaire** - Skip sections based on answers (no pain → skip pain details)
2. **Quick mode** - Just core 5 questions for busy mornings
3. **Trend detection** - "You've reported headaches 4 of last 7 days"
4. **Provider alerts** - Flag patterns that warrant discussion
5. **Pre-fill defaults** - Remember typical answers, highlight changes

**Provider Report Section:**

```
MORNING SYMPTOM TRENDS (Last 30 Days)
────────────────────────────────────────
Sleep Quality Average:     3.2/5 ⭐
Rested Feeling:           Moderate (58%)
                          
PAIN FREQUENCY:
  Lower back:             12 days (40%)
  Neck:                   8 days (27%)
  Headache:               6 days (20%)

RESPIRATORY:
  Congestion:             4 days (13%)
  
NARCOLEPSY SYMPTOMS:
  Sleep paralysis:        3 episodes
  Hypnopompic halluc.:    1 episode
  
NOTABLE PATTERNS:
  ⚠️ Lower back pain correlates with 
     nights with >3 wake events (r=0.67)
  ⚠️ Headaches more common after 
     dose intervals <155 minutes
```

Correlate with previous night's data.

---

## Phase 7: Daytime Narcolepsy Tracking

### 7.1 Cataplexy Episodes

| Field | Options |
|-------|---------|
| **Severity** | Mild (weakness) / Moderate (partial collapse) / Severe (full collapse) |
| **Trigger** | Laughter / Surprise / Anger / Stress / None identified |
| **Duration** | <30s / 30s-2m / 2-5m / >5m |
| **Location** | Home / Work / Public / Driving (alert!) |

### 7.2 Sleep Attacks

- Unplanned naps (time, duration, location)
- Irresistible sleepiness rating (1-10)
- Activity when occurred (driving, working, eating, etc.)

### 7.3 Other Narcolepsy Symptoms

- Hypnagogic hallucinations (falling asleep)
- Hypnopompic hallucinations (waking up)
- Sleep paralysis episodes
- Automatic behaviors (doing things without awareness)

---

## Phase 8: Environmental & Lifestyle Factors

### 8.1 Environment

- **Room temperature** (too hot/cold disrupts sleep)
- **Light exposure** (evening blue light tracking via Screen Time API)
- **Noise events** (detected via microphone with permission)
- **Travel/timezone** (jet lag significantly impacts narcolepsy)

### 8.2 Exercise

- **Workout timing** (late exercise can help or hurt)
- **Intensity** (correlate with that night's sleep)
- **Type** (cardio vs strength)

### 8.3 Menstrual Cycle (Optional)

- Cycle phase affects narcolepsy symptoms for many
- Correlate sleep quality with cycle day
- Import from Apple Health if tracked

### 8.4 Stress & Work

- Stress level rating (1-5)
- Work schedule (normal / shift work / travel)
- Weekend vs weekday patterns

---

## Phase 9: Analytics & Insights Engine

### 9.1 Correlation Heatmaps

Visual display of what factors correlate with sleep quality:

```
                    SLEEP QUALITY CORRELATIONS
                    
Factor              Positive    Negative    Strength
─────────────────────────────────────────────────────
Last meal >3h ago      ████████░░              0.72
HRV > 45ms             ███████░░░              0.65
No caffeine after 1pm  ██████░░░░              0.58
Adderall before noon   █████░░░░░              0.51
Exercise that day      ████░░░░░░              0.42
Light dinner           ████░░░░░░              0.41
Weekend                           ███░░░░░░░  -0.28
High stress                       ████░░░░░░  -0.35
Heavy dinner                      █████░░░░░  -0.48
Late stimulant                    ███████░░░  -0.67
```

### 9.2 "Best Night" Profile

Identify what your best nights have in common:
- Average dose interval on good nights
- Common factors (meal timing, med timing, etc.)
- Suggested routine based on data

### 9.3 Trend Analysis

- Week-over-week sleep quality
- 30-day rolling averages
- Seasonal patterns
- Medication effectiveness over time

### 9.4 Anomaly Detection

- "Last night had 3x your average wake events"
- "Your HRV has been declining for 5 days"
- "Sleep efficiency dropped 15% this week"

---

## Phase 10: Provider Integration

### 10.1 Export Features

- **PDF Summary Report** (for doctor visits)
  - Sleep quality trends
  - Dose timing patterns
  - Event frequency charts
  - Medication timing compliance
  
- **CSV Export** (for detailed analysis)
  - All raw data
  - Configurable date ranges
  - HIPAA-conscious (no cloud)

### 10.2 Report Templates

- Monthly summary
- Pre-appointment report
- Medication adjustment tracking
- Symptom frequency report

---

## Phase 11: Smart Automation

### 11.1 Intelligent Reminders

| Trigger | Reminder |
|---------|----------|
| 2h after last logged meal | "Safe window for Dose 1 opening" |
| Dose 1 taken | "Dose 2 window opens at [time]" |
| 15min before optimal interval | "Optimal Dose 2 time approaching" |
| Stimulant cutoff time | "Last call for afternoon stimulant" |
| Caffeine cutoff | "Consider switching to decaf" |

### 11.2 Shortcuts Integration

- "Hey Siri, log my dinner"
- "Hey Siri, when can I take Dose 1?"
- "Hey Siri, how did I sleep?"
- Widget for quick meal/caffeine logging

### 11.3 Focus Mode Integration

- Auto-enable Sleep Focus when Dose 1 taken
- Bedtime routine automation

---

## Phase 12: Complication & Widget Suite

### watchOS Complications

- **Current phase** (waiting / window open / near close)
- **Countdown timer** (to window open or close)
- **Quick log button** (bathroom/water one-tap)
- **Last dose time**

### iOS Widgets

- **Tonight status** (small: phase + timer)
- **Quick actions** (medium: dose + event buttons)
- **Sleep quality trend** (large: 7-day chart)
- **Lock screen** (dose timer countdown)

---

## Technical Architecture Notes

### Data Schema Evolution

```sql
-- New tables for enhanced tracking
CREATE TABLE medications (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    half_life_hours REAL,
    created_at TEXT NOT NULL
);

CREATE TABLE medication_doses (
    id TEXT PRIMARY KEY,
    medication_id TEXT NOT NULL,
    dose_mg REAL NOT NULL,
    taken_at TEXT NOT NULL,
    notes TEXT,
    FOREIGN KEY (medication_id) REFERENCES medications(id)
);

CREATE TABLE meals (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    size TEXT NOT NULL,
    fat_content TEXT,
    notes TEXT
);

CREATE TABLE biometric_snapshots (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    heart_rate REAL,
    hrv REAL,
    spo2 REAL,
    respiratory_rate REAL,
    body_temp REAL,
    sleep_stage TEXT,
    source TEXT NOT NULL  -- 'apple_health' | 'whoop'
);

CREATE TABLE daytime_symptoms (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    type TEXT NOT NULL,  -- 'cataplexy' | 'sleep_attack' | 'hallucination' | etc
    severity TEXT,
    trigger TEXT,
    duration_seconds INTEGER,
    notes TEXT
);

CREATE TABLE morning_checkins (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    sleep_quality INTEGER,  -- 1-5
    grogginess TEXT,
    dream_recall TEXT,
    ready_for_day BOOLEAN,
    notes TEXT,
    FOREIGN KEY (session_id) REFERENCES current_session(id)
);
```

### Privacy Principles

1. **Local-first**: All data stays on device by default
2. **No cloud requirement**: Works fully offline
3. **Export control**: User owns their data
4. **Optional sync**: iCloud backup only if enabled
5. **No tracking**: Zero analytics/telemetry
6. **HIPAA-conscious**: Designed for medical sensitivity

---

## Implementation Priority

### Immediate (Next Release)
1. Meal timing tracker (critical for XYWAV)
2. Last meal → Dose 1 safety check
3. Morning check-in survey

### Short-term (Q1)
1. Medication tracking (stimulants first)
2. Basic biometric correlation (HR, HRV)
3. Sleep quality derived metrics

### Medium-term (Q2)
1. Full HealthKit biometric suite
2. Cataplexy/symptom logging
3. Insights engine v1 (correlations)

### Long-term (Q3+)
1. Provider export reports
2. Smart automation
3. Advanced analytics
4. Widget suite

---

## Why This Matters

Narcolepsy affects ~1 in 2,000 people. XYWAV is a life-changing medication but requires precise timing and lifestyle coordination that no general sleep app addresses.

**DoseTap can become:**
- The first app that truly understands XYWAV's requirements
- A comprehensive narcolepsy management tool
- A data source for meaningful provider conversations
- A personal research tool for optimizing individual treatment

**The goal isn't feature bloat** — it's surfacing the correlations that help each user find *their* optimal routine. Every person with narcolepsy has a different pattern. DoseTap should help them discover it.

---

*"The best sleep tracker is the one that helps you understand YOUR sleep."*
