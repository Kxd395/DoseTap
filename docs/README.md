# DoseTap Documentation

> **Last Updated:** 2025-12-23 | **SSOT Version:** 2.0.0 | **Tests:** 95 passing

## 🎯 Primary Reference

### Single Source of Truth (SSOT)
**[📁 SSOT/](SSOT/)** - The authoritative specification folder

- **[SSOT/README.md](SSOT/README.md)** ⭐ - Complete v2.0.0 specification (CURRENT)
- **[SSOT/navigation.md](SSOT/navigation.md)** - Quick navigation guide
- **[SSOT/contracts/](SSOT/contracts/)** - API specs and schemas

## ⏱️ Core Timing Parameters (AUTHORITATIVE)

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Window Opens** | 150 minutes | After Dose 1 |
| **Window Closes** | 240 minutes | Hard limit, doses blocked |
| **Default Target** | 165 minutes | User configurable |
| **Valid Targets** | 165, 180, 195, 210, 225 min | Only 5 options |
| **Snooze Duration** | 10 minutes | Fixed |
| **Max Snoozes** | 3 per night | Resets each session |
| **Snooze Disabled** | <15 min remaining | Safety rule |
| **Undo Window** | 5 seconds | All dose actions |
| **On-Time** | ±10 min of target | Adherence metric |

## ✅ Implementation Status

### Phase 1: Sleep Event Logging ✅ COMPLETE
| Feature | Status | Tests |
|---------|--------|-------|
| SleepEvent model (12 types) | ✅ Complete | 29 tests |
| EventRateLimiter | ✅ Complete | Cooldowns work |
| SQLite sleep_events table | ✅ Complete | CRUD ops |
| QuickLogPanel UI | ✅ Complete | 4x3 grid |
| TimelineView | ✅ Complete | Expandable sessions |
| UnifiedSleepSession | ✅ Complete | Data model |

### Core Features ✅ COMPLETE
| Feature | Status | Tests |
|---------|--------|-------|
| Dose Window Logic | ✅ Complete | 13 tests |
| API Client & Errors | ✅ Complete | 23 tests |
| Offline Queue | ✅ Complete | 4 tests |
| CRUD Actions | ✅ Complete | 25 tests |
| **Total Tests** | **95 passing** | All green |

### Phase 2: Health Dashboard 🔄 IN PROGRESS
| Feature | Status |
|---------|--------|
| SleepDataAggregator | 📋 Planned |
| HeartRateChartView | 📋 Planned |
| WHOOPRecoveryCard | 📋 Planned |
| Correlation Insights | 📋 Planned |

### Data Integration Status
| Source | Status | Notes |
|--------|--------|-------|
| SQLite Storage | ✅ Complete | 4 tables |
| Apple HealthKit | ✅ Ready | HR, HRV, sleep |
| WHOOP API | ✅ Connected | Tokens verified |

## �️ Sleep Event Types (12 total)

| Event | Cooldown | Category |
|-------|----------|----------|
| `bathroom` 🚽 | 60s | Physical |
| `water` 💧 | 5m | Physical |
| `snack` 🍴 | 15m | Physical |
| `lightsOut` 💡 | 1h | Sleep Cycle |
| `wakeFinal` ☀️ | 1h | Sleep Cycle |
| `wakeTemp` 🌙 | 5m | Sleep Cycle |
| `anxiety` 🧠 | 5m | Mental |
| `dream` ☁️ | 60s | Mental |
| `heartRacing` ❤️ | 5m | Mental |
| `noise` 🔊 | 60s | Environment |
| `temperature` 🌡️ | 5m | Environment |
| `pain` 🩹 | 5m | Environment |

## 📚 Supporting Documentation

| Document | Purpose |
|----------|---------|
| [PRD.md](PRD.md) | Product requirements |
| [FEATURE_ROADMAP.md](FEATURE_ROADMAP.md) | Development phases |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Technical plan |
| [USE_CASES.md](USE_CASES.md) | User workflows |
| [architecture.md](architecture.md) | System design |

## 🔍 Quick Reference

| What You Need | Where to Find It |
|--------------|------------------|
| **Core specs** | [SSOT/README.md](SSOT/README.md) |
| **Timing logic** | [SSOT/README.md#dose-timing-parameters](SSOT/README.md#dose-timing-parameters-authoritative) |
| **Sleep events** | [SSOT/README.md#sleep-event-system](SSOT/README.md#sleep-event-system-new-in-v20) |
| **API endpoints** | [SSOT/README.md#api-contract](SSOT/README.md#api-contract) |
| **Error codes** | [SSOT/README.md#error-codes--ux](SSOT/README.md#error-codes--ux) |

## 🚀 For Contributors

### Before You Start
1. **Read [SSOT/README.md](SSOT/README.md)** - Complete specification (canonical)
2. Run tests: `swift test -q` (123 tests must pass)
3. Check [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for current tasks

### Key Principles
- **SSOT is authoritative** - Update SSOT first, then code
- **XYWAV-only** - No multi-medication features  
- **150-240 min window** - Never violated
- **Offline-first** - All features work without connection
- **Test-driven** - All core logic has unit tests

## 📋 File Structure

```

### When Adding Features
1. Update [SSOT/README.md](SSOT/README.md) first (canonical SSOT)
2. Add to appropriate section
3. Update navigation if needed
4. Run `swift test -q` (123 tests must pass)
5. Submit PR with "Docs: " prefix

### Documentation Structure
```
docs/
├── SSOT/                   # Single Source of Truth (authoritative)
│   ├── README.md          # ⭐ Canonical SSOT specification
│   ├── navigation.md      # Navigation guide
│   └── contracts/         # Technical contracts
│       ├── api.openapi.yaml
│       ├── schemas/       # JSON schemas
│       └── diagrams/      # Mermaid diagrams
├── archive/               # Archived historical docs
│   └── SSOT_v2.md         # Frozen historical reference
├── README.md              # This file
├── IMPLEMENTATION_PLAN.md # Feature implementation roadmap
└── ...
```

## 🔗 External Resources

- [XYWAV Prescribing Information](https://www.xywav.com)
- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [WHOOP Developer API](https://developer.whoop.com/)
- [Apple HealthKit Documentation](https://developer.apple.com/documentation/healthkit)

---

**Remember:** The SSOT folder contains everything. Start with [SSOT/README.md](SSOT/README.md) for the canonical specification.

**Current Status:** 123 tests passing • 12 sleep event types • 4 tabs (Tonight, Timeline, Dashboard, Settings) • HealthKit + WHOOP ready
