import Foundation

// MARK: - Event Models
public struct DoseEvent: Codable, Identifiable, Equatable {
    public let id: UUID
    public let type: DoseEventType
    public let timestamp: Date
    public let metadata: [String: String]
    
    public init(type: DoseEventType, timestamp: Date = Date(), metadata: [String: String] = [:]) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public enum DoseEventType: String, Codable, CaseIterable {
    case dose1 = "dose1"
    case dose2 = "dose2"
    case snooze = "snooze"
    case skip = "skip"
    case bathroom = "bathroom"
    case lightsOut = "lights_out"
    case wakeFinal = "wake_final"
}

// MARK: - Health Data Models
public struct HealthData: Codable {
    public let sleepStart: Date?
    public let sleepEnd: Date?
    public let timeToFirstWake: TimeInterval?
    public let totalSleepTime: TimeInterval?
    public let deepSleepTime: TimeInterval?
    public let remSleepTime: TimeInterval?
    public let timestamp: Date
    
    public init(sleepStart: Date? = nil, sleepEnd: Date? = nil, timeToFirstWake: TimeInterval? = nil,
                totalSleepTime: TimeInterval? = nil, deepSleepTime: TimeInterval? = nil, 
                remSleepTime: TimeInterval? = nil, timestamp: Date = Date()) {
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.timeToFirstWake = timeToFirstWake
        self.totalSleepTime = totalSleepTime
        self.deepSleepTime = deepSleepTime
        self.remSleepTime = remSleepTime
        self.timestamp = timestamp
    }
}

public struct WHOOPData: Codable {
    public let cycleId: String?
    public let sleepStart: Date?
    public let sleepEnd: Date?
    public let timeToFirstWake: TimeInterval?
    public let sleepScore: Int?
    public let recoveryScore: Int?
    public let strain: Double?
    public let hrv: Double?
    public let restingHeartRate: Int?
    public let timestamp: Date
    
    public init(cycleId: String? = nil, sleepStart: Date? = nil, sleepEnd: Date? = nil,
                timeToFirstWake: TimeInterval? = nil, sleepScore: Int? = nil, recoveryScore: Int? = nil,
                strain: Double? = nil, hrv: Double? = nil, restingHeartRate: Int? = nil, timestamp: Date = Date()) {
        self.cycleId = cycleId
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.timeToFirstWake = timeToFirstWake
        self.sleepScore = sleepScore
        self.recoveryScore = recoveryScore
        self.strain = strain
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.timestamp = timestamp
    }
}

// MARK: - Unified Data Container
public struct DoseSessionData: Codable {
    public let sessionId: UUID
    public let events: [DoseEvent]
    public let healthData: HealthData?
    public let whoopData: WHOOPData?
    public let startTime: Date
    public let endTime: Date?
    
    public init(sessionId: UUID = UUID(), events: [DoseEvent] = [], healthData: HealthData? = nil,
                whoopData: WHOOPData? = nil, startTime: Date = Date(), endTime: Date? = nil) {
        self.sessionId = sessionId
        self.events = events
        self.healthData = healthData
        self.whoopData = whoopData
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Data Storage Service
@MainActor
public class DataStorageService: ObservableObject {
    public static let shared = DataStorageService()
    
    @Published public private(set) var currentSession: DoseSessionData?
    @Published public private(set) var historicalSessions: [DoseSessionData] = []
    @Published public private(set) var allEvents: [DoseEvent] = []
    
    private let documentsDirectory: URL
    private let eventsFileURL: URL
    private let sessionsFileURL: URL
    
    private init() {
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.eventsFileURL = documentsDirectory.appendingPathComponent("dose_events.json")
        self.sessionsFileURL = documentsDirectory.appendingPathComponent("dose_sessions.json")
        
        loadStoredData()
    }
    
    // MARK: - Event Management
    public func logEvent(_ type: DoseEventType, metadata: [String: String] = [:]) {
        let event = DoseEvent(type: type, metadata: metadata)
        allEvents.append(event)
        
        // Add to current session or create new one
        if currentSession == nil && type == .dose1 {
            startNewSession()
        }
        
        if var session = currentSession {
            session = DoseSessionData(
                sessionId: session.sessionId,
                events: session.events + [event],
                healthData: session.healthData,
                whoopData: session.whoopData,
                startTime: session.startTime,
                endTime: type == .dose2 ? Date() : session.endTime
            )
            currentSession = session
            
            // Complete session when dose2 is taken
            if type == .dose2 {
                completeCurrentSession()
            }
        }
        
        saveEventsToFile()
    }
    
    public func startNewSession() {
        if let session = currentSession {
            // Save incomplete session to history
            historicalSessions.append(session)
        }
        
        currentSession = DoseSessionData(startTime: Date())
        saveSessionsToFile()
    }
    
    public func completeCurrentSession() {
        guard let session = currentSession else { return }
        
        let completedSession = DoseSessionData(
            sessionId: session.sessionId,
            events: session.events,
            healthData: session.healthData,
            whoopData: session.whoopData,
            startTime: session.startTime,
            endTime: Date()
        )
        
        historicalSessions.append(completedSession)
        currentSession = nil
        saveSessionsToFile()
    }
    
    // MARK: - Health Data Integration
    public func updateCurrentSessionHealthData(_ healthData: HealthData) {
        guard var session = currentSession else { return }
        
        session = DoseSessionData(
            sessionId: session.sessionId,
            events: session.events,
            healthData: healthData,
            whoopData: session.whoopData,
            startTime: session.startTime,
            endTime: session.endTime
        )
        currentSession = session
        saveSessionsToFile()
    }
    
    public func updateCurrentSessionWHOOPData(_ whoopData: WHOOPData) {
        guard var session = currentSession else { return }
        
        session = DoseSessionData(
            sessionId: session.sessionId,
            events: session.events,
            healthData: session.healthData,
            whoopData: whoopData,
            startTime: session.startTime,
            endTime: session.endTime
        )
        currentSession = session
        saveSessionsToFile()
    }
    
    // MARK: - Data Access
    public func getAllSessions() -> [DoseSessionData] {
        var sessions = historicalSessions
        if let current = currentSession {
            sessions.append(current)
        }
        return sessions.sorted { $0.startTime > $1.startTime }
    }
    
    public func getSessionsInDateRange(start: Date, end: Date) -> [DoseSessionData] {
        return getAllSessions().filter { session in
            session.startTime >= start && session.startTime <= end
        }
    }
    
    public func getRecentEvents(limit: Int = 50) -> [DoseEvent] {
        return Array(allEvents.suffix(limit).reversed())
    }
    
    // MARK: - Export Functionality
    public func exportToCSV() -> String {
        var csv = "Session ID,Event ID,Event Type,Timestamp,Sleep Start,Sleep End,Time to First Wake,WHOOP Sleep Score,WHOOP Recovery Score,Metadata\n"
        
        for session in getAllSessions() {
            for event in session.events {
                let sleepStart = session.healthData?.sleepStart?.ISO8601Format() ?? ""
                let sleepEnd = session.healthData?.sleepEnd?.ISO8601Format() ?? ""
                let ttfw = session.healthData?.timeToFirstWake?.description ?? ""
                let sleepScore = session.whoopData?.sleepScore?.description ?? ""
                let recoveryScore = session.whoopData?.recoveryScore?.description ?? ""
                let metadata = event.metadata.map { "\($0.key):\($0.value)" }.joined(separator: ";")
                
                csv += "\(session.sessionId),\(event.id),\(event.type.rawValue),\(event.timestamp.ISO8601Format()),\(sleepStart),\(sleepEnd),\(ttfw),\(sleepScore),\(recoveryScore),\"\(metadata)\"\n"
            }
        }
        
        return csv
    }
    
    public func getStorageInfo() -> (eventsCount: Int, sessionsCount: Int, fileSize: String, location: String) {
        let eventsCount = allEvents.count
        let sessionsCount = historicalSessions.count + (currentSession != nil ? 1 : 0)
        
        let fileSize: String
        do {
            let eventsSize = try eventsFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let sessionsSize = try sessionsFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let totalSize = eventsSize + sessionsSize
            fileSize = ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
        } catch {
            fileSize = "Unknown"
        }
        
        return (eventsCount, sessionsCount, fileSize, documentsDirectory.path)
    }
    
    // MARK: - Data Persistence
    private func loadStoredData() {
        loadEvents()
        loadSessions()
    }
    
    private func loadEvents() {
        guard FileManager.default.fileExists(atPath: eventsFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: eventsFileURL)
            allEvents = try JSONDecoder().decode([DoseEvent].self, from: data)
        } catch {
            print("Failed to load events: \(error)")
        }
    }
    
    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: sessionsFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: sessionsFileURL)
            let sessions = try JSONDecoder().decode([DoseSessionData].self, from: data)
            
            // Separate current session from historical
            let incompleteSessions = sessions.filter { $0.endTime == nil }
            historicalSessions = sessions.filter { $0.endTime != nil }
            currentSession = incompleteSessions.last // Take most recent incomplete session
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
    
    private func saveEventsToFile() {
        do {
            let data = try JSONEncoder().encode(allEvents)
            try data.write(to: eventsFileURL)
        } catch {
            print("Failed to save events: \(error)")
        }
    }
    
    private func saveSessionsToFile() {
        var allSessions = historicalSessions
        if let current = currentSession {
            allSessions.append(current)
        }
        
        do {
            let data = try JSONEncoder().encode(allSessions)
            try data.write(to: sessionsFileURL)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }
    
    // MARK: - Data Management
    public func clearAllData() {
        allEvents.removeAll()
        historicalSessions.removeAll()
        currentSession = nil
        
        try? FileManager.default.removeItem(at: eventsFileURL)
        try? FileManager.default.removeItem(at: sessionsFileURL)
    }
    
    public func deleteSession(_ sessionId: UUID) {
        historicalSessions.removeAll { $0.sessionId == sessionId }
        if currentSession?.sessionId == sessionId {
            currentSession = nil
        }
        saveSessionsToFile()
    }
}
