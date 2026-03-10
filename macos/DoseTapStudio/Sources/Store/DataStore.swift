import Foundation
import Combine

/// Main data store for DoseTap Studio that manages all imported data
@MainActor
final class DataStore: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var events: [DoseEvent] = []
    @Published private(set) var sessions: [DoseSession] = []
    @Published private(set) var inventory: [InventorySnapshot] = []
    @Published private(set) var insightSessions: [InsightSession] = []
    @Published private(set) var analytics: DoseTapAnalytics = .empty
    @Published var folderURL: URL?
    @Published private(set) var lastImported: Date?
    @Published private(set) var importStatus: ImportStatus = .none
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let importer = Importer()
    private let insightBuilder = InsightSessionBuilder()
    
    enum ImportStatus: Equatable {
        case none
        case importing
        case success(Int) // event count
        case error(String)
    }
    
    init() {
        // Observe folder changes and auto-refresh
        $folderURL
            .compactMap { $0 }
            .sink { [weak self] url in
                Task { @MainActor in
                    await self?.loadAll(from: url)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Load all data from the specified folder
    func loadAll(from folder: URL) async {
        guard importStatus != .importing else { return }
        
        importStatus = .importing
        
        do {
            self.folderURL = folder
            
            // Load all data types
            let loadedEvents = try await importer.loadEvents(from: folder)
            let loadedSessions = try await importer.loadSessions(from: folder)
            let loadedInventory = try await importer.loadInventory(from: folder)
            let loadedInsightsBundle = try await importer.loadInsightsBundle(from: folder)
            let supplementsBySessionDate = Dictionary(
                uniqueKeysWithValues: (loadedInsightsBundle?.sessions ?? []).map { ($0.sessionDate, $0) }
            )
            
            // Sort and update
            self.events = loadedEvents.sorted { $0.occurredAtUTC < $1.occurredAtUTC }
            self.sessions = loadedSessions.sorted { $0.startedUTC < $1.startedUTC }
            self.inventory = loadedInventory.sorted { $0.asOfUTC > $1.asOfUTC }
            self.insightSessions = insightBuilder.build(
                sessions: self.sessions,
                events: self.events,
                supplementsBySessionDate: supplementsBySessionDate
            )
            
            // Update analytics
            self.analytics = calculateAnalytics(from: insightSessions)
            
            // Update status
            self.lastImported = Date()
            self.importStatus = .success(loadedEvents.count)
            
            print("✅ Imported \(loadedEvents.count) events, \(loadedSessions.count) sessions, \(loadedInventory.count) inventory snapshots")
            
        } catch {
            print("❌ Import error: \(error)")
            self.importStatus = .error(error.localizedDescription)
        }
    }
    
    /// Refresh data from current folder
    func refresh() async {
        guard let folderURL = folderURL else { return }
        await loadAll(from: folderURL)
    }
    
    /// Clear all data
    func clearData() {
        events.removeAll()
        sessions.removeAll()
        inventory.removeAll()
        insightSessions.removeAll()
        analytics = .empty
        folderURL = nil
        lastImported = nil
        importStatus = .none
    }
    
    // MARK: - Analytics Calculations
    
    private func calculateAnalytics(from insightSessions: [InsightSession]) -> DoseTapAnalytics {
        let totalEvents = events.count
        let totalSessions = sessions.count
        
        // Get last 30 days of data
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        let recentInsightSessions = insightSessions.filter { session in
            guard let startedAt = session.startedAt else { return false }
            return startedAt >= thirtyDaysAgo
        }
        
        // Calculate adherence rate
        let adherentSessions = recentInsightSessions.filter { ($0.adherenceFlag ?? "") == "ok" || $0.isOnTimeDose2 }
        let adherenceRate = recentInsightSessions.isEmpty ? 0.0 : (Double(adherentSessions.count) / Double(recentInsightSessions.count)) * 100.0
        
        // Calculate average window time
        let windowTimes = recentInsightSessions.compactMap(\.intervalMinutes)
        let averageWindow = windowTimes.isEmpty ? 0.0 : Double(windowTimes.reduce(0, +)) / Double(windowTimes.count)
        
        // Calculate missed doses
        let missedSessions = recentInsightSessions.filter(\.dose2Skipped)
        let missedDoses = missedSessions.count
        
        // Calculate average WHOOP recovery
        let recoveryValues = recentInsightSessions.compactMap(\.whoopRecovery)
        let averageRecovery = recoveryValues.isEmpty ? nil : Double(recoveryValues.reduce(0, +)) / Double(recoveryValues.count)
        
        // Calculate average heart rate
        let hrValues = recentInsightSessions.compactMap(\.averageHeartRate)
        let averageHR = hrValues.isEmpty ? nil : hrValues.reduce(0, +) / Double(hrValues.count)

        // Calculate average sleep efficiency
        let sleepEfficiencies = recentInsightSessions.compactMap(\.sleepEfficiency)
        let averageSleepEfficiency = sleepEfficiencies.isEmpty ? nil : sleepEfficiencies.reduce(0, +) / Double(sleepEfficiencies.count)
        let nightAggregates = recentInsightSessions.map { session in
            StudioNightAggregate(
                id: session.sessionDate,
                dose1: session.dose1Time,
                dose2: session.dose2Time,
                dose2Skipped: session.dose2Skipped,
                intervalMinutes: session.intervalMinutes,
                eventCount: session.eventCount,
                bathroomEvents: session.bathroomCount,
                lightsOutEvents: session.lightsOutCount,
                wakeFinalEvents: session.wakeFinalCount,
                sleepEfficiency: session.sleepEfficiency,
                whoopRecovery: session.whoopRecovery,
                avgHR: session.averageHeartRate
            )
        }

        let qualityIssueNights = nightAggregates.filter { !$0.qualityFlags.isEmpty }.count
        let highConfidenceNights = nightAggregates.filter { $0.completenessScore >= 0.7 }.count
        let averageEventsPerNight = nightAggregates.isEmpty
            ? 0
            : Double(nightAggregates.reduce(0) { $0 + $1.eventCount }) / Double(nightAggregates.count)
        
        return DoseTapAnalytics(
            totalEvents: totalEvents,
            totalSessions: totalSessions,
            adherenceRate30d: adherenceRate,
            averageWindow30d: averageWindow,
            missedDoses30d: missedDoses,
            averageRecovery30d: averageRecovery,
            averageHR30d: averageHR,
            averageSleepEfficiency30d: averageSleepEfficiency,
            averageEventsPerNight30d: averageEventsPerNight,
            qualityIssueNights30d: qualityIssueNights,
            highConfidenceNights30d: highConfidenceNights,
            nights: nightAggregates
        )
    }

    // MARK: - Filtered Data Access
    
    /// Get events for a specific date range
    func events(from startDate: Date, to endDate: Date) -> [DoseEvent] {
        return events.filter { event in
            event.occurredAtUTC >= startDate && event.occurredAtUTC <= endDate
        }
    }
    
    /// Get sessions for a specific date range
    func sessions(from startDate: Date, to endDate: Date) -> [DoseSession] {
        return sessions.filter { session in
            session.startedUTC >= startDate && session.startedUTC <= endDate
        }
    }
    
    /// Get dose pairs (D1 -> D2) for timeline visualization
    func dosePairs() -> [(dose1: DoseEvent, dose2: DoseEvent?)] {
        let dose1Events = events.filter { $0.eventType == .dose1_taken }
        var pairs: [(dose1: DoseEvent, dose2: DoseEvent?)] = []
        
        for dose1 in dose1Events {
            // Find corresponding dose2 within reasonable window (up to 4 hours)
            let windowEnd = dose1.occurredAtUTC.addingTimeInterval(4 * 60 * 60)
            let dose2 = events.first { event in
                (event.eventType == .dose2_taken || event.eventType == .dose2_skipped) &&
                event.occurredAtUTC > dose1.occurredAtUTC &&
                event.occurredAtUTC <= windowEnd
            }
            pairs.append((dose1: dose1, dose2: dose2))
        }
        
        return pairs
    }
    
    /// Get current inventory status
    var currentInventory: InventorySnapshot? {
        return inventory.first // Already sorted by date (newest first)
    }
}
