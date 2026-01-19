# Audit Log

## Session Start
- Date: 2026-01-19 11:52
- Environment:
  - macOS version: 15.7.4 (24G508)
  - Xcode version: 26.2 (17C52)
  - Swift version: 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
  - iOS Simulator: iPhone 16 Pro, iOS 18.6 (available)
  - Build scheme: DoseTap
  - Build flags: SwiftPM default Debug (no explicit flags)

## Commands Executed
| Time | Command | Result | Notes |
|------|---------|--------|-------|
| 11:52 | sw_vers | Success | Captured macOS version |
| 11:52 | xcodebuild -version | Success | Captured Xcode version |
| 11:52 | swift --version | Success | Captured Swift version |
| 11:52 | xcrun simctl list devices available | Success | Simulator inventory |
| 11:52 | xcodebuild -list -project ios/DoseTap.xcodeproj | Success | Schemes/targets |
| 11:52 | swift build 2>&1 \| tee build.log | Success w/ warning | 1 SwiftPM resource warning |
| 11:52 | swift test -q 2>&1 \| tee test.log | Success | 277 tests passed; TimeIntervalMath warning logged |
| 11:53 | rg --files | Success | Repository file inventory |
| 11:53 | tree -a -L 3 | Success | Repository map snapshot |
| 11:53 | rg -n "History" ios | Success | Located History/Timeline references |
| 11:53 | rg --files -g "*SSOT*" | Success | SSOT doc discovery |
| 11:53 | cat docs/SSOT/README.md | Success | SSOT review |
| 11:53 | cat docs/SSOT/constants.json | Success | SSOT constants review |
| 11:53 | cat docs/DATABASE_SCHEMA.md | Success | Schema reference |
| 11:54 | sed -n 1,260p ios/DoseTap/Storage/EventStorage.swift | Success | Storage review |
| 11:54 | sed -n 1,260p ios/DoseTap/Storage/SessionRepository.swift | Success | Storage SSOT review |
| 11:54 | sed -n 1,260p ios/DoseTap/ContentView.swift | Success | UI flow review |
| 11:54 | sed -n 240,640p ios/DoseTap/SettingsView.swift | Success | Export/UI review |
| 11:55 | sed -n 1,260p ios/DoseTap/FullApp/TimelineView.swift | Success | Timeline review |
| 11:55 | sed -n 1,260p ios/DoseTap/UserSettingsManager.swift | Success | Settings + event types |
| 11:55 | sed -n 1,240p ios/Core/SleepEvent.swift | Success | Event type SSOT |
| 11:55 | sed -n 1,240p ios/Core/DoseWindowState.swift | Success | Dose window rules |
| 11:55 | sed -n 1,240p ios/Core/DoseTapCore.swift | Success | Core SSOT |
| 11:55 | sed -n 1,220p ios/Core/SessionKey.swift | Success | Session key/rollover |
| 11:56 | sed -n 1,220p ios/DoseTap/Security/InputValidator.swift | Success | Event validation |
| 11:56 | sed -n 1,220p ios/DoseTap/Security/DatabaseSecurity.swift | Success | Encryption review |
| 11:56 | sed -n 1,220p ios/DoseTap/Security/SecureLogger.swift | Success | Logging review |
| 11:56 | sed -n 1,220p ios/DoseTap/SecureConfig.swift | Success | Secrets handling |
| 12:20 | rg --files \| wc -l | Success | Counted total files |
| 12:20 | rg -n "class EventLogger\|struct EventLogger\|func logEvent" ios/DoseTap | Success | Event logger locations |
| 12:20 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '1,120p' | Success | EventLogger line refs |
| 12:20 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '230,330p' | Success | TabView wiring refs |
| 12:20 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '1400,1660p' | Success | CompactDoseButton + snooze refs |
| 12:20 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '2260,2440p' | Success | DetailsView + QuickLog refs |
| 12:20 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '3000,3200p' | Success | FullEventLogGrid refs |
| 12:20 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '3300,3455p' | Success | Alternate snooze refs |
| 12:20 | nl -ba ios/DoseTap/Storage/EventStorage.swift \| sed -n '60,200p' | Success | Table DDL refs |
| 12:20 | nl -ba ios/DoseTap/Storage/EventStorage.swift \| sed -n '340,460p' | Success | Session_id backfill refs |
| 12:20 | nl -ba ios/DoseTap/Storage/EventStorage.swift \| sed -n '560,760p' | Success | insertSleepEvent session_id fallback |
| 12:20 | nl -ba ios/DoseTap/Storage/EventStorage.swift \| sed -n '880,980p' | Success | saveDose1/saveDose2 refs |
| 12:20 | nl -ba ios/DoseTap/Storage/EventStorage.swift \| sed -n '1020,1125p' | Success | time edit refs |
| 12:20 | nl -ba ios/DoseTap/Storage/EventStorage.swift \| sed -n '2480,2685p' | Success | exportToCSVv2 + escapeCSV refs |
| 12:20 | nl -ba ios/DoseTap/Storage/SessionRepository.swift \| sed -n '200,420p' | Success | session rollover refs |
| 12:20 | nl -ba ios/DoseTap/Storage/SessionRepository.swift \| sed -n '500,640p' | Success | setDose1/2 refs |
| 12:20 | nl -ba ios/DoseTap/Storage/SessionRepository.swift \| sed -n '820,900p' | Success | wake_final refs |
| 12:20 | nl -ba ios/DoseTap/Storage/SessionRepository.swift \| sed -n '1300,1390p' | Success | fetchTonightSleepEvents refs |
| 12:20 | nl -ba ios/DoseTap/Storage/SessionRepository.swift \| sed -n '1450,1505p' | Success | exportToCSVv2 refs |
| 12:20 | nl -ba ios/DoseTap/UserSettingsManager.swift \| sed -n '80,200p' | Success | QuickLog defaults + cooldowns |
| 12:20 | nl -ba ios/DoseTap/UserSettingsManager.swift \| sed -n '240,310p' | Success | cooldown name mapping |
| 12:20 | nl -ba ios/Core/SleepEvent.swift \| sed -n '1,220p' | Success | SSOT cooldowns + display names |
| 12:20 | nl -ba ios/Core/DoseWindowState.swift \| sed -n '1,220p' | Success | snooze rules refs |
| 12:20 | nl -ba ios/Core/SessionKey.swift \| sed -n '1,200p' | Success | session key 6pm boundary |
| 12:20 | nl -ba ios/DoseTap/SleepStageTimeline.swift \| sed -n '540,640p' | Success | timeline dose events refs |
| 12:20 | nl -ba ios/DoseTap/FullApp/TimelineView.swift \| sed -n '620,820p' | Success | event type mapping refs |
| 12:20 | nl -ba ios/DoseTap/URLRouter.swift \| sed -n '150,320p' | Success | deep link event mapping refs |
| 12:20 | nl -ba ios/DoseTap/Security/InputValidator.swift \| sed -n '1,200p' | Success | event validation refs |
| 12:20 | nl -ba ios/DoseTap/AlarmService.swift \| sed -n '180,240p' | Success | snooze logic refs |
| 12:20 | nl -ba ios/DoseTap/SettingsView.swift \| sed -n '520,620p' | Success | export UI refs |
| 12:20 | nl -ba docs/SSOT/constants.json \| sed -n '1,200p' | Success | SSOT constants refs |
| 12:30 | rg --files -g '*View*.swift' ios/DoseTap | Success | View inventory |
| 12:30 | rg -n "session_id" docs/SSOT | Success | SSOT session_id refs |
| 12:30 | nl -ba docs/SSOT/README.md \| sed -n '1,120p' | Success | SSOT identity/invariants refs |
| 12:30 | rg --files -g '*xcprivacy*' | Not found | No privacy manifest |
| 12:30 | rg -n "warning" build.log | Success | Build warning refs |
| 12:30 | sed -n '1,40p' build.log | Success | Build log context |
| 12:30 | rg -n "TimeIntervalMath" test.log | Success | Test log warning ref |
| 12:30 | nl -ba ios/Core/TimeIntervalMath.swift \| sed -n '1,200p' | Success | TimeIntervalMath warning source |
| 12:30 | rg -n "PersistentStore" ios | Success | CoreData usage refs |
| 12:30 | nl -ba ios/DoseTap/Persistence/PersistentStore.swift \| sed -n '1,200p' | Success | CoreData store refs |
| 12:30 | nl -ba ios/DoseTap/Export/CSVExporter.swift \| sed -n '1,200p' | Success | CoreData CSV exporter refs |
| 12:30 | nl -ba ios/DoseTap/Storage/JSONMigrator.swift \| sed -n '1,120p' | Success | JSON migration refs |
| 12:30 | nl -ba ios/DoseTap/Storage/EncryptedEventStorage.swift \| sed -n '1,200p' | Success | Encrypted storage refs |
| 12:30 | rg -n "ActivityViewController" ios/DoseTap | Success | Share sheet helper refs |
| 12:30 | nl -ba ios/DoseTap/Views/NightReviewView.swift \| sed -n '640,720p' | Success | Night review export refs |
| 12:30 | nl -ba ios/DoseTap/SupportBundleExport.swift \| sed -n '430,480p' | Success | Support bundle share sheet refs |
| 12:30 | rg -n "exportURL\\|ActivityViewController\\|export" ios/DoseTap/SettingsView.swift | Success | Export UI wiring refs |
| 12:30 | nl -ba ios/DoseTap/SettingsView.swift \| sed -n '240,420p' | Success | Export section refs |
| 12:30 | rg -n "sessionDidChange" ios/DoseTap | Success | Session update signals |
| 12:30 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '640,760p' | Success | sessionDidChange hooks |
| 12:30 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '2438,2800p' | Success | History view refs |
| 12:30 | nl -ba ios/DoseTap/DoseTapApp.swift \| sed -n '1,200p' | Success | App entry/lifecycle refs |
| 12:30 | nl -ba Package.swift \| sed -n '1,200p' | Success | SwiftPM target refs |
| 12:30 | rg -n "SessionRepository\\|saveMorningCheckIn\\|save" ios/DoseTap/Views/MorningCheckInView.swift | Success | Check-in save refs |
| 12:30 | nl -ba ios/DoseTap/Views/MorningCheckInView.swift \| sed -n '360,460p' | Success | Morning check-in submit refs |
| 12:30 | rg -n "submit\\|SessionRepository\\|saveMorningCheckIn" ios/DoseTap/Views/MorningCheckInViewV2.swift | Success | Check-in V2 refs |
| 12:30 | nl -ba ios/DoseTap/Views/MorningCheckInViewV2.swift \| sed -n '160,240p' | Success | Check-in V2 save refs |
| 12:30 | rg -n "SessionRepository\\|EventStorage\\|save" ios/DoseTap/Views/PreSleepLogView.swift | Success | Pre-sleep save refs |
| 12:30 | nl -ba ios/DoseTap/Views/PreSleepLogView.swift \| sed -n '150,240p' | Success | Pre-sleep save refs |
| 12:30 | rg -n "save\\|SessionRepository\\|EventStorage" ios/DoseTap/Views/PreSleepLogViewV2.swift | Success | Pre-sleep V2 refs |
| 12:30 | nl -ba ios/DoseTap/Views/PreSleepLogViewV2.swift \| sed -n '190,260p' | Success | Pre-sleep V2 save refs |
| 12:30 | nl -ba ios/DoseTap/Views/EditDoseTimeView.swift \| sed -n '1,200p' | Success | Edit dose/event view refs |
| 12:30 | nl -ba ios/DoseTap/Views/MedicationSettingsView.swift \| sed -n '1,200p' | Success | Medication settings refs |
| 12:30 | nl -ba ios/DoseTap/Views/MedicationPickerView.swift \| sed -n '1,200p' | Success | Medication picker refs |
| 12:30 | nl -ba ios/DoseTap/Views/MedicationPickerView.swift \| sed -n '300,420p' | Success | Medication save refs |
| 12:30 | nl -ba ios/DoseTap/Views/ThemeSettingsView.swift \| sed -n '1,200p' | Success | Theme settings refs |
| 12:30 | nl -ba ios/DoseTap/Views/DiagnosticExportView.swift \| sed -n '1,200p' | Success | Diagnostic export refs |
| 12:30 | nl -ba ios/DoseTap/WHOOPSettingsView.swift \| sed -n '1,200p' | Success | WHOOP settings refs |
| 12:30 | nl -ba ios/DoseTap/SleepPlanDetailView.swift \| sed -n '1,200p' | Success | Sleep plan detail refs |
| 12:30 | nl -ba ios/DoseTap/DiagnosticLoggingSettingsView.swift \| sed -n '1,200p' | Success | Diagnostic logging settings refs |
| 12:30 | python3 - ... (repo_map generator) | Success | Generated repo_map.md |
| 12:38 | rg -c "func test" Tests/DoseCoreTests/*.swift | Success | Test count inventory |
| 12:38 | rg --files Tests/DoseCoreTests | Success | Test file list |
| 12:38 | rg -n "Wake" ios/DoseTap/ContentView.swift | Success | Wake flow refs |
| 12:38 | rg -n "struct LegacyTonightView" ios/DoseTap/ContentView.swift | Success | Tonight view location |
| 12:38 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '360,520p' | Success | LegacyTonightView refs |
| 12:38 | nl -ba ios/DoseTap/ContentView.swift \| sed -n '2060,2185p' | Success | WakeUpButton refs |
| 12:44 | rg -n "PRODUCT_BUNDLE_IDENTIFIER" ios/DoseTap.xcodeproj/project.pbxproj | Success | Bundle id lookup |
| 12:44 | open -a Simulator | Success | Launch Simulator |
| 12:44 | xcrun simctl list devices available \| rg "iPhone 16 Pro" | Success | Device inventory |
| 12:44 | xcrun simctl boot "iPhone 16 Pro" | Success | Boot device |
| 12:44 | xcrun simctl bootstatus "iPhone 16 Pro" -b | Success | Boot status |
| 12:45 | xcodebuild -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -configuration Debug -derivedDataPath ios/build/DerivedData build \| tee ios_build.log | Success | iOS app build |
| 12:46 | xcrun simctl install booted ios/build/DerivedData/Build/Products/Debug-iphonesimulator/DoseTap.app | Success | Installed app on booted device |
| 12:46 | xcrun simctl launch booted com.dosetap.ios | Success | Launched app |
| 12:47 | xcrun simctl openurl booted "dosetap://dose1" | Success | Deep link dose1 |
| 12:47 | xcrun simctl openurl booted "dosetap://dose2" | Success | Deep link dose2 |
| 12:47 | xcrun simctl openurl booted "dosetap://log?event=lightsout" | Success | Deep link log event |
| 12:47 | xcrun simctl get_app_container booted com.dosetap.ios data | Success | App container path |
| 12:47 | sqlite3 ... \"select event_type, count(*) from dose_events group by event_type;\" | Success | Dose events query |
| 12:47 | sqlite3 ... \"select event_type, count(*) from sleep_events group by event_type;\" | Success | Sleep events query |
| 12:48 | xcrun simctl list devices booted | Success | Booted devices list |
| 12:48 | xcrun simctl terminate 41BA2FD7-F982-4D70-95CF-0A40BD1B18FD com.dosetap.ios | Success | Restart app on Pro Max |
| 12:48 | xcrun simctl launch 41BA2FD7-F982-4D70-95CF-0A40BD1B18FD com.dosetap.ios | Success | Relaunch app on Pro Max |
| 12:48 | xcrun simctl openurl 41BA2FD7-F982-4D70-95CF-0A40BD1B18FD "dosetap://dose1" | Success | Deep link dose1 (Pro Max) |
| 12:48 | xcrun simctl openurl 41BA2FD7-F982-4D70-95CF-0A40BD1B18FD "dosetap://dose2" | Success | Deep link dose2 (Pro Max) |
| 12:48 | xcrun simctl openurl 41BA2FD7-F982-4D70-95CF-0A40BD1B18FD "dosetap://log?event=lightsout" | Success | Deep link log event (Pro Max) |
| 12:49 | sqlite3 ... \"select event_type, count(*) from dose_events group by event_type;\" | Success | Dose events query (Pro Max) |
| 12:49 | sqlite3 ... \"select count(*) from sleep_events;\" | Success | Sleep events count (Pro Max) |
| 12:50 | cat > docs/FIX_PLAN_AUDIT_FOLLOWUP.md | Success | Fix plan created |
| 12:50 | cat > ios/DoseTap/PrivacyInfo.xcprivacy | Success | Privacy manifest created (UserDefaults only) |
| 13:24 | xcrun simctl listapps booted \| rg -i dosetap | Success | Verified only `com.dosetap.ios` installed |
| 13:24 | xcrun simctl launch booted com.dosetap.ios | Success | Relaunched app (correct bundle) |
| 13:24 | xcrun simctl openurl booted "dosetap://log?event=bathroom" | Success | Deep link log event attempt |
| 13:24 | xcrun simctl get_app_container booted com.dosetap.ios data | Success | App container path |
| 13:24 | sqlite3 ... ".tables" | Success | Table inventory for dosetap_events.sqlite |
| 13:24 | sqlite3 ... "select count(*) from sleep_events;" | Success | Sleep events count (0) |
| 13:24 | sqlite3 ... "select count(*) from dose_events;" | Success | Dose events count (0) |
| 13:24 | sqlite3 ... "select count(*) from current_session;" | Success | Current session count (0) |
| 13:24 | sqlite3 ... "select count(*) from sleep_sessions;" | Success | Sleep sessions count (0) |
| 13:24 | xcrun simctl io booted screenshot /tmp/dosetap_sim.png | Success | Screenshot captured (deep link prompt) |
| 13:53 | xcrun simctl openurl booted "dosetap://dose1" | Success | Deep link dose1 (booted device) |
| 13:53 | sqlite3 ... "select * from dose_events;" | Success | Dose events rows (non-empty) |
| 13:53 | sqlite3 ... "select * from current_session;" | Success | Current session row present |
| 13:53 | sqlite3 ... "select * from sleep_events;" | Success | Sleep events rows (non-empty) |
| 13:53 | find "$CONTAINER" -name "*.sqlite" -o -name "*.db" | Success | DB path check |
| 13:53 | sqlite3 ... "select count(*) from dose_events; ..." | Success | Dose/sleep counts + latest timestamps |
| 13:53 | sqlite3 ... "select event_type, timestamp, session_date, session_id from dose_events order by timestamp desc limit 5;" | Success | Recent dose_events |
| 13:53 | sqlite3 ... "select event_type, timestamp, session_date, session_id from sleep_events order by timestamp desc limit 5;" | Success | Recent sleep_events |
| 13:53 | xcrun simctl list devices booted | Success | Two booted devices (iPhone 16 Pro, iPhone 17 Pro) |
| 14:08 | xcrun simctl shutdown all | Success | Consolidate to single device |
| 14:08 | xcrun simctl boot "iPhone 16 Pro" | Success | Boot iPhone 16 Pro only |
| 14:08 | xcrun simctl bootstatus "iPhone 16 Pro" -b | Success | Boot status |
| 14:08 | xcrun simctl uninstall 68ED545A-77F0-42AC-A45B-4BD2A04071EF com.dosetap.ios | Success | Clean uninstall |
| 14:08 | xcrun simctl install 68ED545A-77F0-42AC-A45B-4BD2A04071EF ios/build/Build/Products/Debug-iphonesimulator/DoseTap.app | Success | Install on iPhone 16 Pro |
| 14:08 | xcrun simctl launch 68ED545A-77F0-42AC-A45B-4BD2A04071EF com.dosetap.ios | Success | Launch app |
| 14:08 | xcrun simctl openurl 68ED545A-77F0-42AC-A45B-4BD2A04071EF "dosetap://dose1" | Success | Deep link dose1 (prompt displayed) |
| 14:08 | xcrun simctl io 68ED545A-77F0-42AC-A45B-4BD2A04071EF screenshot /tmp/dosetap_16pro_prompt.png | Success | Screenshot captured (deep link prompt) |
| 14:21 | xcrun simctl launch 68ED545A-77F0-42AC-A45B-4BD2A04071EF com.dosetap.ios | Success | Relaunch app (iPhone 16 Pro) |
| 14:21 | xcrun simctl openurl 68ED545A-77F0-42AC-A45B-4BD2A04071EF "dosetap://dose1" | Success | Deep link dose1 (prompt still displayed) |
| 14:21 | xcrun simctl openurl 68ED545A-77F0-42AC-A45B-4BD2A04071EF "dosetap://log?event=bathroom" | Success | Deep link log event (prompt still displayed) |
| 14:21 | xcrun simctl openurl 68ED545A-77F0-42AC-A45B-4BD2A04071EF "dosetap://log?event=lightsout" | Success | Deep link log event (prompt still displayed) |
| 14:21 | sqlite3 ... "select count(*) as dose_count ...; select count(*) as sleep_count ...; select count(*) as session_count ...;" | Success | Counts remain 0 (no prompt acceptance) |
| 14:21 | xcrun simctl io 68ED545A-77F0-42AC-A45B-4BD2A04071EF screenshot /tmp/dosetap_16pro_after_deeplink.png | Success | Screenshot captured (prompt still present) |
| 14:33 | xcrun simctl listapps 41F614B8-CBEF-4E64-B572-0B40CE467A76 \| rg -i dosetap | Success | Verified com.dosetap.ios installed on iPhone 17 Pro |
| 14:33 | xcrun simctl get_app_container 41F614B8-CBEF-4E64-B572-0B40CE467A76 com.dosetap.ios data | Success | App container path (iPhone 17 Pro) |
| 14:33 | sqlite3 ... "select count(*) as dose_count ...; select count(*) as sleep_count ...; select count(*) as session_count ...;" | Success | Counts: dose_events=8, sleep_events=38, current_session=1 |
| 14:33 | sqlite3 ... "select event_type, timestamp, session_date, session_id from dose_events order by timestamp desc limit 10;" | Success | Recent dose_events (dose1/dose2) |
| 14:33 | sqlite3 ... "select event_type, timestamp, session_date, session_id from sleep_events order by timestamp desc limit 10;" | Success | Recent sleep_events (Title Case + lightsOut) |
| 14:33 | sqlite3 ... "select distinct event_type from sleep_events union select distinct event_type from dose_events order by event_type;" | Success | Event type inventory (mixed casing + duplicates) |
| 14:55 | xcrun simctl list devices booted | Success | No booted devices |
| 14:55 | xcrun simctl boot "iPhone 17 Pro" | Success | Booted new iPhone 17 Pro (C67F7A43...) |
| 14:55 | xcrun simctl shutdown C67F7A43-B204-4088-AAEE-9F7CED5C147E | Success | Shutdown temporary device |
| 14:55 | xcrun simctl boot 41F614B8-CBEF-4E64-B572-0B40CE467A76 | Success | Booted iPhone 17 Pro (existing data) |
| 14:55 | xcrun simctl bootstatus 41F614B8-CBEF-4E64-B572-0B40CE467A76 -b | Success | Boot status |
| 14:55 | xcrun simctl listapps 41F614B8-CBEF-4E64-B572-0B40CE467A76 \| rg -i dosetap | Success | com.dosetap.ios installed |
| 14:55 | xcrun simctl launch 41F614B8-CBEF-4E64-B572-0B40CE467A76 com.dosetap.ios | Success | Launch app (prepare for export) |
| 15:14 | ls -la docs/review/DoseTap_Export_2026-01-19_145947.csv | Success | CSV export file exists |
| 15:14 | python3 - ... (BOM check) | Success | No UTF-8 BOM |
| 15:14 | python3 - ... (section inventory) | Success | 7 sections, 85 lines |
| 15:14 | python3 - ... (row counts per section) | Success | sleep_events=29, dose_events=9, sessions=5, morning_checkins=5, pre_sleep_logs=6, medication_events=0, sleep_sessions=8 |
| 15:14 | python3 - ... (event type sets) | Success | sleep_events and dose_events distinct types captured |
| 15:14 | python3 - ... (sample rows) | Success | Verified CSV parsing and JSON fields |
| 15:14 | python3 - ... (CRLF check) | Success | LF-only line endings |
| 15:14 | python3 - ... (row length check) | Success | No column count mismatches |
| 15:36 | xcodebuild -project ios/DoseTap.xcodeproj -scheme DoseTap -sdk iphonesimulator -configuration Debug -derivedDataPath ios/build | Success | Rebuild after normalization + dedupe changes |
| 15:36 | xcrun simctl install 41F614B8-CBEF-4E64-B572-0B40CE467A76 ios/build/Build/Products/Debug-iphonesimulator/DoseTap.app | Success | Installed updated build on iPhone 17 Pro |
| 15:36 | xcrun simctl launch 41F614B8-CBEF-4E64-B572-0B40CE467A76 com.dosetap.ios | Success | Launched updated build |
| 16:05 | sqlite3 ... "select event_type, timestamp, session_date from sleep_events order by timestamp desc limit 20;" | Success | New normalized sleep_events observed |
| 16:05 | sqlite3 ... "select event_type, timestamp, session_date, metadata from dose_events order by timestamp desc limit 10;" | Success | New dose_events written (dose1/dose2) |
| 16:05 | sqlite3 ... "select distinct event_type from sleep_events order by event_type;" | Success | Mixed legacy + normalized event types present |
| 16:05 | sqlite3 ... "select distinct event_type from dose_events order by event_type;" | Success | dose1/dose2 types |

## Repro Attempts
| Issue | Steps | Outcome | Evidence |
|-------|-------|---------|----------|
| Timeline vs History mismatch | Manual UI (Dose 1, Dose 2 Early, Bathroom, Lights Out) on iPhone 17 Pro | DB populated (dose_events + sleep_events) with mixed event_type casing; UI shows events in both Timeline and History | sqlite3 queries + user screenshots |
| CSV export failure | Not run in UI (no UI automation) | Blocked | HYPOTHESIS - requires manual UI steps |

## Files Reviewed
| Folder | Files | Coverage | Notes |
|--------|-------|----------|-------|
| agent | AUDIT_PROMPT_V3.md | Reviewed | Audit instructions |
| docs/SSOT | README.md, constants.json | Reviewed | SSOT baseline |
| docs | DATABASE_SCHEMA.md | Reviewed | Schema baseline |
| ios/Core | DoseTapCore.swift, DoseWindowState.swift, SessionKey.swift, SleepEvent.swift, TimeIntervalMath.swift | Reviewed | Core logic |
| ios/DoseTap/Storage | EventStorage.swift, SessionRepository.swift, JSONMigrator.swift, EncryptedEventStorage.swift | Reviewed | Persistence + migration |
| ios/DoseTap | ContentView.swift, SettingsView.swift, UserSettingsManager.swift, URLRouter.swift, DoseTapApp.swift | Reviewed | UI + routing |
| ios/DoseTap/FullApp | TimelineView.swift, DataExportService.swift, SQLiteStorage.swift | Reviewed | Alternate UI path |
| ios/DoseTap/Persistence | PersistentStore.swift, FetchHelpers.swift | Reviewed | CoreData split |
| ios/DoseTap/Security | InputValidator.swift, DatabaseSecurity.swift, SecureLogger.swift | Reviewed | Security |

## Decisions Made
| Decision | Rationale | Evidence |
|----------|-----------|----------|
| Use SwiftPM build/test | Required by audit workflow | `build.log`, `test.log` |
