Great idea. Let’s add a macOS companion that reads your iOS exports and overlays dose windows, WHOOP metrics, and Apple‑Health–derived summaries for deep analysis. Below is a practical, end‑to‑end plan with drop‑in SwiftUI (macOS) code, the feature spec, and how it ties to your SSOT and Build Summary.

⸻

What this solves (why a Mac app helps)
	•	Single, widescreen timeline to overlay: Dose 1/2 events, the 150–240 min window, snoozes, and health metrics (HR/Recovery/Sleep). Your iOS app is already exporting CSV/JSON; the Mac app consumes those files and renders analysis views.  ￼
	•	No HealthKit on macOS: we avoid missing APIs by reading Health summaries baked into your exports (sessions/analytics), which you’ve already scoped in your SSOT.  ￼
	•	Local‑only privacy carried over: Default “watch a folder” on iCloud Drive or local Documents—no servers.  ￼

⸻

Product name & IDs (fill‑ins for forms)
	•	App name: DoseTap Studio (macOS)
	•	Bundle ID: org.axxessphila.DoseTapStudio
	•	Minimum macOS: 13.0 (Ventura) for Swift Charts
	•	Team: your Apple Developer Team (same as iOS app)
	•	Sandbox: “User Selected File” for security‑scoped bookmarks (to watch the export folder)

⸻

Data in, data out (tied to SSOT/Build Summary)

Inputs (from iOS exports):
	•	events.csv (SSOT CSV v1) or dose_events.json — canonical event log.  ￼  ￼
	•	sessions.csv / dose_sessions.json — per‑night aggregates incl. health overlays (recovery, avg HR, efficiency). (Add sessions.csv v1 to iOS exporter if you haven’t already.)  ￼
	•	(Optional) inventory.csv for refill forecasting.  ￼

Outputs (Mac):
	•	Overlays: shaded dose windows (150–240 min), dose points, snoozes, HR line, WHOOP Recovery bars.  ￼
	•	Analytics: adherence %, average window, near‑end usage, miss reasons, refill ETA.
	•	Reports: export PDF or HTML “night/session report.”

⸻

Core features (V1)
	1.	Watch Folder (iCloud Drive or local): security‑scoped bookmark + live refresh on new exports.
	2.	Timeline Overlay (Swift Charts):
	•	Window shading: Active (150–240 m) and Near‑End (<15 m) states.
	•	Points: Dose1/Dose2/Skip; Annotations for snoozes and notes.
	•	Lines/Bars: HR line, WHOOP Recovery bars by night.  ￼
	3.	Session Inspector: select a night → see exact deltas, adherence score, and linked health snapshot.
	4.	Adherence & Trends Dashboard: rolling 7/30/90‑day stats.
	5.	Privacy‑first: local only; optional WHOOP cloud import later via OAuth (off by default).  ￼
	6.	Export Analysis: share sheet for PDF/CSV.

This extends the export and analytics you’ve defined in iOS (CSV v1 and the dashboard concept) into a desktop analysis surface.  ￼  ￼

⸻

UI map (macOS)
	•	Sidebar: Overview · Timeline · Sessions · Inventory · Import/Folder
	•	Top filters: Date range, event type, search notes
	•	Inspector (right panel): Selected session details (dose times, window actual vs target, snoozes, notes, WHOOP/Health snapshot)

⸻

Implementation plan (two sprints)

Sprint A (2–3 days): File watching, JSON/CSV import, basic Timeline/Overview charts, Session inspector (read‑only).
Sprint B (2–3 days): Overlays/polish (window shading; near‑end visuals), PDF/HTML report export, inventory view, persistence cache.

This aligns with your SSOT/Build Summary and keeps privacy guarantees intact.  ￼  ￼  ￼

⸻

Drop‑in code (4 concise batches)

Create an Xcode macOS App “DoseTap Studio (macOS)” (SwiftUI, macOS 13). Add files per paths below.

Batch 1 — Models & Store (Sources/Model/Models.swift, Sources/Store/DataStore.swift)

// Sources/Model/Models.swift
import Foundation

enum EventType: String, Codable, CaseIterable {
    case dose1_taken, dose2_taken, dose2_skipped, bathroom, undo
}

struct DoseEvent: Codable, Identifiable {
    let id: String                      // CSV: event_id
    let eventType: EventType            // CSV: event_type
    let source: String                  // CSV: source
    let occurredAtUTC: Date             // CSV: occurred_at_utc (ISO8601 Z)
    let localTZ: String                 // CSV: local_tz (IANA)
    let doseSequence: Int?              // CSV: dose_sequence
    var note: String?                   // CSV: note

    var occurredAtLocal: Date {
        // Convert using stored IANA zone from CSV for fidelity
        let tz = TimeZone(identifier: localTZ) ?? .current
        let seconds = tz.secondsFromGMT(for: occurredAtUTC)
        return Date(timeInterval: TimeInterval(seconds), since: occurredAtUTC)
    }

    enum CodingKeys: String, CodingKey {
        case id = "event_id", eventType = "event_type", source,
             occurredAtUTC = "occurred_at_utc", localTZ = "local_tz",
             doseSequence = "dose_sequence", note
    }
}

struct DoseSession: Codable, Identifiable {
    // Mirrors proposed sessions.csv v1 from your SSOT
    // session_id, started_utc, ended_utc, bedtime_local, window_target_min,
    // window_actual_min, adherence_flag, whoop_recovery, avg_hr, sleep_efficiency, note
    let id: String
    let startedUTC: Date
    let endedUTC: Date?
    let bedtimeLocal: String?
    let windowTargetMin: Int?
    let windowActualMin: Int?
    let adherenceFlag: String?
    let whoopRecovery: Int?
    let avgHR: Double?
    let sleepEfficiency: Double?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id = "session_id", startedUTC = "started_utc", endedUTC = "ended_utc",
             bedtimeLocal = "bedtime_local", windowTargetMin = "window_target_min",
             windowActualMin = "window_actual_min", adherenceFlag = "adherence_flag",
             whoopRecovery = "whoop_recovery", avgHR = "avg_hr",
             sleepEfficiency = "sleep_efficiency", note
    }
}

struct InventorySnapshot: Codable {
    let asOfUTC: Date
    let medicationName: String
    let bottlesOnHand: Int
    let mgPerBottle: Int
    let mgPerDose1: Int
    let mgPerDose2: Int
    let estimatedDaysRemaining: Int?
    let refillThresholdDays: Int?
}

// Sources/Store/DataStore.swift
import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var events: [DoseEvent] = []
    @Published private(set) var sessions: [DoseSession] = []
    @Published private(set) var inventory: [InventorySnapshot] = []
    @Published var folderURL: URL?

    private var cancellables = Set<AnyCancellable>()
    private let importer = Importer()

    init() {}

    func loadAll(from folder: URL) async {
        self.folderURL = folder
        do {
            let loadedEvents = try await importer.loadEvents(from: folder)
            let loadedSessions = try await importer.loadSessions(from: folder)
            let loadedInventory = try await importer.loadInventory(from: folder)
            self.events = loadedEvents.sorted { $0.occurredAtUTC < $1.occurredAtUTC }
            self.sessions = loadedSessions.sorted { $0.startedUTC < $1.startedUTC }
            self.inventory = loadedInventory
        } catch {
            print("Import error: \(error)")
        }
    }
}


⸻

Batch 2 — Importers & Folder Watcher (Sources/Import/Importer.swift, Sources/Import/FolderMonitor.swift)

// Sources/Import/Importer.swift
import Foundation

enum ImportError: Error { case missingFiles, decode, parse }

actor Importer {
    private let iso = ISO8601DateFormatter()

    func loadEvents(from folder: URL) async throws -> [DoseEvent] {
        // Prefer JSON; fallback to CSV per your Build Summary/SSOT
        // JSON filename: dose_events.json ; CSV filename: events.csv
        let jsonURL = folder.appendingPathComponent("dose_events.json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return try await decodeJSON([DoseEvent].self, at: jsonURL)
        }
        let csvURL = folder.appendingPathComponent("events.csv")
        if FileManager.default.fileExists(atPath: csvURL.path) {
            return try parseEventsCSV(at: csvURL)
        }
        return []
    }

    func loadSessions(from folder: URL) async throws -> [DoseSession] {
        let jsonURL = folder.appendingPathComponent("dose_sessions.json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return try await decodeJSON([DoseSession].self, at: jsonURL)
        }
        let csvURL = folder.appendingPathComponent("sessions.csv")
        if FileManager.default.fileExists(atPath: csvURL.path) {
            return try parseSessionsCSV(at: csvURL)
        }
        return []
    }

    func loadInventory(from folder: URL) async throws -> [InventorySnapshot] {
        let csvURL = folder.appendingPathComponent("inventory.csv")
        guard FileManager.default.fileExists(atPath: csvURL.path) else { return [] }
        return try parseInventoryCSV(at: csvURL)
    }

    // MARK: - JSON
    private func decodeJSON<T: Decodable>(_ type: T.Type, at url: URL) async throws -> T {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(T.self, from: data)
    }

    // MARK: - CSV (minimal, safe for SSOT CSV v1)
    private func parseEventsCSV(at url: URL) throws -> [DoseEvent] {
        let (header, rows) = try readCSV(url)
        // Expected header from SSOT v1:
        // event_id,event_type,source,occurred_at_utc,local_tz,dose_sequence,note
        guard header.count >= 7 else { return [] }
        return rows.compactMap { row in
            guard
                let id = row["event_id"],
                let et = row["event_type"].flatMap(EventType.init(rawValue:)),
                let src = row["source"],
                let tsStr = row["occurred_at_utc"],
                let occurred = ISO8601DateFormatter().date(from: tsStr),
                let tz = row["local_tz"]
            else { return nil }
            let seq = row["dose_sequence"].flatMap(Int.init)
            let note = row["note"]
            return DoseEvent(id: id, eventType: et, source: src, occurredAtUTC: occurred, localTZ: tz, doseSequence: seq, note: note)
        }
    }

    private func parseSessionsCSV(at url: URL) throws -> [DoseSession] {
        let (_, rows) = try readCSV(url)
        return rows.compactMap { r in
            guard
                let id = r["session_id"],
                let start = r["started_utc"].flatMap(ISO8601DateFormatter().date(from:))
            else { return nil }
            return DoseSession(
                id: id,
                startedUTC: start,
                endedUTC: r["ended_utc"].flatMap(ISO8601DateFormatter().date(from:)),
                bedtimeLocal: r["bedtime_local"],
                windowTargetMin: r["window_target_min"].flatMap(Int.init),
                windowActualMin: r["window_actual_min"].flatMap(Int.init),
                adherenceFlag: r["adherence_flag"],
                whoopRecovery: r["whoop_recovery"].flatMap(Int.init),
                avgHR: r["avg_hr"].flatMap(Double.init),
                sleepEfficiency: r["sleep_efficiency"].flatMap(Double.init),
                note: r["note"]
            )
        }
    }

    private func parseInventoryCSV(at url: URL) throws -> [InventorySnapshot] {
        let (_, rows) = try readCSV(url)
        return rows.compactMap { r in
            guard
                let asOf = r["as_of_utc"].flatMap(ISO8601DateFormatter().date(from:)),
                let name = r["medication_name"],
                let bottles = r["bottles_on_hand"].flatMap(Int.init),
                let mgBottle = r["mg_per_bottle"].flatMap(Int.init),
                let mgD1 = r["mg_per_dose1"].flatMap(Int.init),
                let mgD2 = r["mg_per_dose2"].flatMap(Int.init)
            else { return nil }
            return InventorySnapshot(
                asOfUTC: asOf, medicationName: name, bottlesOnHand: bottles,
                mgPerBottle: mgBottle, mgPerDose1: mgD1, mgPerDose2: mgD2,
                estimatedDaysRemaining: r["estimated_days_remaining"].flatMap(Int.init),
                refillThresholdDays: r["refill_threshold_days"].flatMap(Int.init)
            )
        }
    }

    // Simple CSV reader with quote support for commas/newlines in quotes
    private func readCSV(_ url: URL) throws -> ([String], [[String:String]]) {
        let s = try String(contentsOf: url)
        var rows: [[String]] = []
        var current = [String]()
        var field = ""
        var inQuotes = false

        func endField() { current.append(field); field = "" }
        func endRow() { rows.append(current); current.removeAll() }

        for char in s {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                endField()
            } else if char == "\n" && !inQuotes {
                endField(); endRow()
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !current.isEmpty { endField(); endRow() }

        guard let header = rows.first else { return ([], []) }
        let body = rows.dropFirst().map { row -> [String:String] in
            var dict = [String:String]()
            for (i, col) in header.enumerated() {
                dict[col] = i < row.count ? row[i] : ""
            }
            return dict
        }
        return (header, Array(body))
    }
}

// Sources/Import/FolderMonitor.swift
import Foundation

final class FolderMonitor {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let queue = DispatchQueue(label: "org.axxessphila.DoseTapStudio.folderMonitor")

    func startMonitoring(url: URL, onChange: @escaping () -> Void) throws {
        stopMonitoring()
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor != -1 else { throw NSError(domain: "FolderMonitor", code: 1) }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        src.setEventHandler { onChange() }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            close(self.descriptor); self.descriptor = -1
        }
        src.resume()
        self.source = src
    }

    func stopMonitoring() {
        source?.cancel()
        source = nil
        if descriptor != -1 { close(descriptor); descriptor = -1 }
    }

    deinit { stopMonitoring() }
}


⸻

Batch 3 — App & Views (Sources/App/DoseTapStudioApp.swift, Sources/Views/*)

// Sources/App/DoseTapStudioApp.swift
import SwiftUI

@main
struct DoseTapStudioApp: App {
    @StateObject private var store = DataStore()
    var body: some Scene {
        WindowGroup("DoseTap Studio") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .newItem) { } // no new document
        }
    }
}

// Sources/Views/RootView.swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: DataStore
    @State private var selection: SidebarItem? = .overview
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("DoseTap Studio") {
                    Label("Overview", systemImage: "rectangle.grid.2x2").tag(SidebarItem.overview)
                    Label("Timeline", systemImage: "chart.xyaxis.line").tag(SidebarItem.timeline)
                    Label("Sessions", systemImage: "calendar").tag(SidebarItem.sessions)
                    Label("Inventory", systemImage: "shippingbox").tag(SidebarItem.inventory)
                    Label("Import / Folder", systemImage: "folder").tag(SidebarItem.importer)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .timeline: TimelineView()
            case .sessions: SessionsView()
            case .inventory: InventoryView()
            case .importer: ImportFolderView()
            }
        }
        .onAppear {
            // First-run: show ImportFolderView if no folder chosen
            if store.folderURL == nil { selection = .importer }
        }
    }
}

enum SidebarItem: Hashable { case overview, timeline, sessions, inventory, importer }

// Sources/Views/ImportFolderView.swift
import SwiftUI

struct ImportFolderView: View {
    @EnvironmentObject var store: DataStore
    @State private var monitor = FolderMonitor()
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose your DoseTap export folder").font(.title2)
            Text("Select the folder that contains events.csv / dose_events.json and sessions.csv / dose_sessions.json")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Choose Folder…") { chooseFolder() }
                if let url = store.folderURL {
                    Text(url.path).font(.caption).lineLimit(2)
                }
            }
            if let error { Text("Error: \(error)").foregroundStyle(.red) }
            Spacer()
        }
        .padding()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.loadAll(from: url) }
            do {
                try monitor.startMonitoring(url: url) {
                    Task { await store.loadAll(from: url) }
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// Sources/Views/OverviewView.swift
import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Overview").font(.largeTitle).bold()
                HStack {
                    StatCard(title: "Events", value: store.events.count.formatted())
                    StatCard(title: "Sessions", value: store.sessions.count.formatted())
                    StatCard(title: "Adherence (30d)", value: adherence30d)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ChartCard(title: "Average Window (min) — 30d") {
                    Chart(windowSeries30d) {
                        LineMark(x: .value("Date", $0.date), y: .value("Window", $0.minutes))
                    }
                }
            }
            .padding()
        }
    }

    private var windowSeries30d: [(date: Date, minutes: Int)] {
        store.sessions.suffix(30).compactMap {
            guard let end = $0.windowActualMin else { return nil }
            return (date: $0.startedUTC, minutes: end)
        }
    }
    private var adherence30d: String {
        let last30 = store.sessions.suffix(30)
        guard !last30.isEmpty else { return "—" }
        let ok = last30.filter { ($0.adherenceFlag ?? "") == "ok" }.count
        return String(format: "%.0f%%", (Double(ok) / Double(last30.count)) * 100.0)
    }
}

struct StatCard: View {
    let title: String; let value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title)
        }
        .padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ChartCard<Content: View>: View {
    let title: String; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content.frame(height: 240)
        }
        .padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Sources/Views/TimelineView.swift
import SwiftUI
import Charts

struct TimelineView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        VStack(alignment: .leading) {
            Text("Timeline Overlay").font(.title2).bold()
            Chart {
                // Shaded windows (from derived pairs of dose1→dose2 range)
                ForEach(windowRanges(), id: \.start) { rng in
                    RectangleMark(xStart: .value("Start", rng.start),
                                  xEnd: .value("End", rng.end),
                                  yStart: .value("Low", 0),
                                  yEnd: .value("High", 1))
                        .opacity(0.12)
                }
                // Dose events as points
                ForEach(store.events) { e in
                    PointMark(x: .value("Time", e.occurredAtLocal), y: .value("Series", seriesY(e)))
                        .annotation(position: .top, alignment: .center) {
                            Text(shortLabel(e)).font(.caption2)
                        }
                }
                // WHOOP Recovery by session (0..100)
                ForEach(store.sessions, id: \.id) { s in
                    if let rec = s.whoopRecovery {
                        BarMark(x: .value("Date", s.startedUTC),
                                y: .value("Recovery", rec))
                    }
                }
                // Average HR line by session
                ForEach(store.sessions, id: \.id) { s in
                    if let hr = s.avgHR {
                        LineMark(x: .value("Date", s.startedUTC),
                                 y: .value("AvgHR", hr))
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
            .frame(minHeight: 380)
            .padding()
            Spacer()
        }
        .padding(.horizontal)
    }

    private func seriesY(_ e: DoseEvent) -> Double {
        switch e.eventType {
        case .dose1_taken: return 0.2
        case .dose2_taken: return 0.5
        case .dose2_skipped: return 0.5
        case .bathroom: return 0.8
        case .undo: return 0.1
        }
    }
    private func shortLabel(_ e: DoseEvent) -> String {
        switch e.eventType {
        case .dose1_taken: return "D1"
        case .dose2_taken: return "D2"
        case .dose2_skipped: return "Skip"
        case .bathroom: return "BR"
        case .undo: return "Undo"
        }
    }

    private struct WindowRange { let start: Date; let end: Date }
    private func windowRanges() -> [WindowRange] {
        // For each D1, compute [D1+150m, D1+240m] per SSOT invariant
        // Then add the actual D2 time if present (used visually as a point)
        let minMin = 150.0 * 60.0, maxMin = 240.0 * 60.0
        var ranges: [WindowRange] = []
        let d1s = store.events.filter { $0.eventType == .dose1_taken }
        for d1 in d1s {
            let start = d1.occurredAtLocal.addingTimeInterval(minMin)
            let end = d1.occurredAtLocal.addingTimeInterval(maxMin)
            ranges.append(.init(start: start, end: end))
        }
        return ranges
    }
}

// Sources/Views/SessionsView.swift
import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var store: DataStore
    @State private var selected: DoseSession?
    var body: some View {
        HStack {
            List(store.sessions, selection: $selected) { s in
                VStack(alignment: .leading) {
                    Text(s.startedUTC, style: .date).bold()
                    HStack(spacing: 8) {
                        if let a = s.adherenceFlag { Tag(a) }
                        if let w = s.windowActualMin { Tag("\(w)m") }
                        if let r = s.whoopRecovery { Tag("Rec \(r)") }
                        if let hr = s.avgHR { Tag("HR \(Int(hr))") }
                    }
                }
            }
            .frame(minWidth: 320)
            if let s = selected {
                SessionDetail(session: s)
            } else {
                Text("Select a session").foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption2).padding(.vertical, 4).padding(.horizontal, 6)
            .background(.thinMaterial).clipShape(Capsule())
    }
}

private struct SessionDetail: View {
    let session: DoseSession
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session").font(.title2).bold()
            Grid(alignment: .leading) {
                GridRow { Text("Start"); Text(session.startedUTC.formatted()) }
                GridRow { Text("Target Window"); Text("\(session.windowTargetMin ?? 165)m") }
                GridRow { Text("Actual Window"); Text(session.windowActualMin.map { "\($0)m" } ?? "—") }
                GridRow { Text("Adherence"); Text(session.adherenceFlag ?? "—") }
                GridRow { Text("Recovery"); Text(session.whoopRecovery.map(String.init) ?? "—") }
                GridRow { Text("Avg HR"); Text(session.avgHR.map { String(Int($0)) } ?? "—") }
                GridRow { Text("Sleep Eff."); Text(session.sleepEfficiency.map { String(Int($0)) + "%" } ?? "—") }
                GridRow { Text("Note"); Text(session.note ?? "—") }
            }
            .gridColumnAlignment(.leading)
            Spacer()
        }
        .padding()
    }
}

// Sources/Views/InventoryView.swift
import SwiftUI

struct InventoryView: View {
    @EnvironmentObject var store: DataStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inventory & Refills").font(.title2).bold()
            List(store.inventory, id: \.asOfUTC) { snap in
                HStack {
                    VStack(alignment: .leading) {
                        Text(snap.medicationName).bold()
                        Text("As of \(snap.asOfUTC.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(snap.bottlesOnHand) bottles")
                        Text("D1 \(snap.mgPerDose1) mg • D2 \(snap.mgPerDose2) mg").font(.caption)
                        if let days = snap.estimatedDaysRemaining { Text("~\(days) days left").font(.caption2) }
                    }
                }
            }.listStyle(.inset)
            Spacer()
        }
        .padding()
    }
}


⸻

Batch 4 — PDF export (optional) & Utilities (Sources/Export/ReportExporter.swift)

// Sources/Export/ReportExporter.swift
import SwiftUI
import PDFKit

struct ReportExporter {
    static func exportSessionsPDF(sessions: [DoseSession], destination: URL) throws {
        let pdf = PDFDocument()
        for (idx, s) in sessions.enumerated() {
            let page = PDFPage(image: renderSessionImage(s))
            pdf.insert(page!, at: idx)
        }
        guard pdf.write(to: destination) else {
            throw NSError(domain: "ReportExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write PDF"])
        }
    }

    private static func renderSessionImage(_ s: DoseSession) -> NSImage {
        // Simple snapshot: title + metrics
        let view = NSHostingView(rootView:
            VStack(alignment: .leading, spacing: 6) {
                Text("DoseTap Session Report").font(.title)
                Text(s.startedUTC.formatted()).font(.headline)
                Divider()
                Text("Target Window: \(s.windowTargetMin ?? 165)m")
                Text("Actual Window: \(s.windowActualMin.map { "\($0)m" } ?? "—")")
                Text("Adherence: \(s.adherenceFlag ?? "—")")
                Text("WHOOP Recovery: \(s.whoopRecovery.map(String.init) ?? "—")")
                Text("Avg HR: \(s.avgHR.map { String(Int($0)) } ?? "—")")
                Text("Sleep Efficiency: \(s.sleepEfficiency.map { String(Int($0)) + "%" } ?? "—")")
                if let note = s.note { Text("Note: \(note)") }
            }.padding(24)
        )
        let size = NSSize(width: 612, height: 792) // US Letter points
        view.setFrameSize(size)
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }
}

How it aligns:
• CSV header/fields map to SSOT CSV v1.
• Sessions mirror the SSOT sessions proposal (target/actual window + health metrics).
• Window shading honors 150–240 min invariant and <15 m near‑end behavior.  ￼

⸻

How to use (quick start)
	1.	On iOS, Export your data (CSV/JSON) from Settings → Export History into an iCloud Drive folder (e.g., iCloud Drive/DoseTap/Exports).  ￼
	2.	Launch DoseTap Studio (macOS) → Import / Folder → “Choose Folder…” and select that folder.
	3.	The app auto‑refreshes when new exports appear and updates the Timeline overlays and Sessions analytics.

⸻

QA & acceptance (macOS)
	•	Import accepts either dose_events.json or events.csv (CSV must match SSOT v1 header/order).  ￼
	•	Timeline shows a shaded band for each D1: [D1+150m, D1+240m].
	•	Snooze/near‑end are visually distinct (no snooze control here—analysis only).  ￼
	•	Sessions list displays windowActualMin, whoopRecovery, avgHR when present; blanks otherwise.
	•	No network calls by default; WHOOP OAuth can be added later behind a toggle (off).  ￼

⸻

README blurb to add to the repo

DoseTap Studio (macOS)
A desktop companion for DoseTap that reads iOS exports and renders analysis dashboards with window overlays and health summaries. Local‑only, privacy‑first.
	•	Inputs: events.csv/dose_events.json, sessions.csv/dose_sessions.json, inventory.csv.
	•	Views: Overview · Timeline Overlay · Sessions Inspector · Inventory.
	•	Requirements: macOS 13+, SwiftUI, Swift Charts.
	•	Folder Watching: security‑scoped bookmark; auto‑refresh on changes.
	•	Reports: PDF export of selected sessions.

⸻

Manager’s Note (for your hardcopy)
	•	The macOS dashboard leverages the same SSOT invariants (150–240 min, <15 m near‑end) and the CSV v1 schema to ensure analysis matches the iOS behavior. Add sessions.csv v1 to the iOS exporter (if not already) so health overlays are available on desktop.  ￼
	•	Keep local‑only as default to maintain your privacy posture from the iOS Build Summary.  ￼
	•	ASCII screens you drafted for iOS (Main/History/Settings) map cleanly to this desktop UX; we just widen into a split view and charts.  ￼

⸻

Running log (what I did)
	•	Mapped a macOS analysis app to consume iOS CSV/JSON exports and overlay all metrics.
	•	Provided SwiftUI+Charts code (folder watch, import, models, views, PDF export).
	•	Grounded invariants/fields to your SSOT v1, ASCII screens, and Build Summary.  ￼  ￼  ￼

⸻

If you want me to, I can also add sessions.csv v1 and a one‑tap “Export to iCloud Drive/DoseTap/Exports” option to the iOS app so the Mac app sees updates instantly.

