# DoseTap SSOT Navigation Guide

Quick links to find exactly what you need in the Single Source of Truth.

> **Note:** This is a pointer document. See [docs/SSOT/README.md](README.md) for the canonical, versioned specification.

## 🎯 Quick Start
- [Core Invariants](README.md#core-invariants) - Medication scope, window rules, safety
- [Navigation Structure](README.md#navigation-structure) - 4-tab swipe navigation
- [Application Architecture](README.md#application-architecture) - Module structure, dependencies
- [State Machine](README.md#screens--states) - Window phases and transitions
- [Button Logic Mapping](README.md#button-logic--components) - Complete component mapping

## 📱 UI & UX Specifications

### 4-Tab Navigation

| Tab | Screen | Key Features |
|-----|--------|--------------|
| 1 | Tonight | Compact layout, no scroll, dose buttons, quick events |
| 2 | Details | Full session info, scrollable event timeline |
| 3 | History | Date picker, view past days, delete per day |
| 4 | Settings | Configuration, data management, multi-select delete |

- [Screens & States](README.md#screens--states) - All app screens with state machines
- [Tonight Screen](README.md#tonight-screen-primary---compact-layout) - Compact primary view
- [History Screen](README.md#history-screen) - Date navigation
- [Data Management](README.md#data-management-screen) - Delete functionality
- [Button Logic & Components](README.md#button-logic--components) - Complete mapping table
- [Accessibility](README.md#accessibility) - Visual, audio, haptic requirements

## 🔌 API & Integration
- [API Contract](README.md#api-contract) - Endpoints, payloads, responses
- [Error Codes & UX](README.md#error-codes--ux) - Error handling and recovery
- [Data Models](README.md#data-models) - Core schemas and types

## 🧠 Business Logic
- [Window Behavior](README.md#window-behavior) - Dose timing rules
- [Planner Algorithm](README.md#planner-client-only) - Interval calculation and safety
- [Safety Constraints](README.md#safety-constraints) - Non-negotiable limits

## ♿ Accessibility & UX
- [Visual Requirements](README.md#visual-requirements) - Contrast, typography, targets
- [Audio & Haptics](README.md#audio--haptics) - VoiceOver, sounds, vibrations
- [Cognitive Accessibility](README.md#cognitive-accessibility) - Clear language and indicators

## 📚 Reference
- [Glossary](README.md#glossary) - Key terms and definitions
- [Definition of Done](README.md#definition-of-done-per-screen) - Completion checklists
- [Version History](README.md#version-history) - Document changelog

## 🔗 Related Documents

### Contracts (Authoritative)
- [**constants.json**](constants.json) - All numeric constants (single source)
- [**DataDictionary.md**](contracts/DataDictionary.md) - Tables, fields, relationships, migration policy
- [**ProductGuarantees.md**](contracts/ProductGuarantees.md) - What the app promises to do correctly
- [api.openapi.yaml](contracts/api.openapi.yaml) - Machine-readable API definition
- [core.json](contracts/schemas/core.json) - JSON Schema definitions
- [State Diagrams](contracts/diagrams/) - Visual state machines

### Other Contracts
- [SetupWizard.md](contracts/SetupWizard.md) - First-run wizard steps
- [SupportBundle.md](contracts/SupportBundle.md) - Export format and privacy
- [Inventory.md](contracts/Inventory.md) - Medication tracking

### Repository
- [Parent Docs](../README.md) - Repository documentation index
- [Architecture](../architecture.md) - Code structure
- [Archive](../../archive/) - Deprecated specs (do not implement from)

## 📋 What Changed?

### 2025-01-06 - SSOT v2.1.0
- ✅ Added 4-tab swipe navigation (Tonight, Details, History, Settings)
- ✅ Compact Tonight screen (no vertical scroll)
- ✅ New History page with date picker
- ✅ Data Management with multi-select deletion
- ✅ Delete from History page (per day with confirmation)
- ✅ Dose events logged in timeline
- ✅ SQLite delete methods (deleteSession, clearAll, clearOld)

### 2024-01-15 - SSOT v1.0.0
- ✅ Consolidated 6 specification documents into single source
- ✅ Added comprehensive button logic mapping with deep links
- ✅ Defined complete API contract with error handling
- ✅ Established WCAG AAA accessibility requirements
- ✅ Created offline-first architecture patterns
- ✅ Added Definition of Done checklists
- ✅ Moved to dedicated SSOT folder structure

### Document Supersession Notice
This SSOT supersedes and replaces:
- `docs/DoseTap_Spec.md` → See [Core Invariants](README.md#core-invariants)
- `docs/ui-ux-specifications.md` → See [Screens & States](README.md#screens--states)
- `docs/button-logic-mapping.md` → See [Button Logic](README.md#button-logic--components)
- `docs/api-documentation.md` → See [API Contract](README.md#api-contract)
- `docs/user-guide.md` → Being rewritten based on SSOT
- `docs/implementation-roadmap.md` → See roadmap based on SSOT

## 🚀 Quick Actions

### For Developers
1. [Component IDs](README.md#button-logic--components) - Find UI component names
2. [API Endpoints](README.md#endpoints) - Get endpoint details
3. [Error Handling](README.md#error-codes--ux) - Handle API errors correctly

### For Designers
1. [Screen States](README.md#screens--states) - Design for all states
2. [Accessibility](README.md#accessibility) - Meet a11y requirements
3. [Visual Requirements](README.md#visual-requirements) - Typography and contrast

### For QA
1. [Definition of Done](README.md#definition-of-done-per-screen) - Test checklists
2. [Error Codes](README.md#error-codes--ux) - Error scenarios to test
3. [Safety Constraints](README.md#safety-constraints) - Critical paths

## 🔍 Search Tips

Use these keywords to find information quickly:
- **Timing**: "window", "interval", "clamp", "150-240"
- **Actions**: "dose1", "dose2", "snooze", "skip", "undo"
- **Components**: "button", "timer", "display", "list"
- **API**: "POST", "GET", "endpoint", "payload", "error"
- **Accessibility**: "VoiceOver", "contrast", "haptic", "WCAG"
