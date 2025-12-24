import Foundation
import Combine

/// Main data store for DoseTap Studio that manages all imported data
@MainActor
final class DataStore: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var events: [DoseEvent] = []
    @Published private(set) var sessions: [DoseSession] = []
    @Published private(set) var inventory: [InventorySnapshot] = []
    @Published private(set) var analytics: DoseTapAnalytics = .empty
    @Published var folderURL: URL?
    @Published private(set) var lastImported: Date?
    @Published private(set) var importStatus: ImportStatus = .none
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let importer = Importer()
    
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
            
            // Sort and update
            self.events = loadedEvents.sorted { $0.occurredAtUTC < $1.occurredAtUTC }
            self.sessions = loadedSessions.sorted { $0.startedUTC < $1.startedUTC }
            self.inventory = loadedInventory.sorted { $0.asOfUTC > $1.asOfUTC }
            
            // Update analytics
            self.analytics = calculateAnalytics()
            
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
        analytics = .empty
        folderURL = nil
        lastImported = nil
        importStatus = .none
    }
    
    // MARK: - Analytics Calculations
    
    private func calculateAnalytics() -> DoseTapAnalytics {
        let totalEvents = events.count
        let totalSessions = sessions.count
        
        // Get last 30 days of data
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        let recentSessions = sessions.filter { $0.startedUTC >= thirtyDaysAgo }
        
        // Calculate adherence rate
        let adherentSessions = recentSessions.filter { ($0.adherenceFlag ?? "") == "ok" }
        let adherenceRate = recentSessions.isEmpty ? 0.0 : (Double(adherentSessions.count) / Double(recentSessions.count)) * 100.0
        
        // Calculate average window time
        let windowTimes = recentSessions.compactMap { $0.windowActualMin }
        let averageWindow = windowTimes.isEmpty ? 0.0 : Double(windowTimes.reduce(0, +)) / Double(windowTimes.count)
        
        // Calculate missed doses
        let missedSessions = recentSessions.filter { ($0.adherenceFlag ?? "") == "missed" }
        let missedDoses = missedSessions.count
        
        // Calculate average WHOOP recovery
        let recoveryValues = recentSessions.compactMap { $0.whoopRecovery }
        let averageRecovery = recoveryValues.isEmpty ? nil : Double(recoveryValues.reduce(0, +)) / Double(recoveryValues.count)
        
        // Calculate average heart rate
        let hrValues = recentSessions.compactMap { $0.avgHR }
        let averageHR = hrValues.isEmpty ? nil : hrValues.reduce(0, +) / Double(hrValues.count)
        
        return DoseTapAnalytics(
            totalEvents: totalEvents,
            totalSessions: totalSessions,
            adherenceRate30d: adherenceRate,
            averageWindow30d: averageWindow,
            missedDoses30d: missedDoses,
            averageRecovery30d: averageRecovery,
            averageHR30d: averageHR
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
