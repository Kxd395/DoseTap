import Foundation

/// Handles importing CSV and JSON data from DoseTap iOS exports
final class Importer {
    
    enum ImportError: LocalizedError {
        case fileNotFound(String)
        case invalidFormat(String)
        case decodingError(String)
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound(let file):
                return "File not found: \(file)"
            case .invalidFormat(let reason):
                return "Invalid format: \(reason)"
            case .decodingError(let reason):
                return "Decoding error: \(reason)"
            }
        }
    }
    
    // MARK: - Event Import
    
    /// Load events from events.csv in the specified folder
    func loadEvents(from folder: URL) async throws -> [DoseEvent] {
        let eventsURL = folder.appendingPathComponent("events.csv")
        
        guard FileManager.default.fileExists(atPath: eventsURL.path) else {
            print("⚠️ events.csv not found in \(folder.path)")
            return []
        }
        
        let content = try String(contentsOf: eventsURL)
        return try parseEventsCSV(content)
    }
    
    func parseEventsCSV(_ content: String) throws -> [DoseEvent] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }
        
        // Skip header line
        let dataLines = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var events: [DoseEvent] = []
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for (index, line) in dataLines.enumerated() {
            do {
                let columns = parseCSVLine(line)
                guard columns.count >= 4 else {
                    print("⚠️ Skipping line \(index + 2): insufficient columns")
                    continue
                }
                
                // Parse event type
                guard let eventType = EventType(rawValue: columns[0]) else {
                    print("⚠️ Skipping line \(index + 2): unknown event type '\(columns[0])'")
                    continue
                }
                
                // Parse timestamp
                guard let occurredAt = formatter.date(from: columns[1]) else {
                    print("⚠️ Skipping line \(index + 2): invalid timestamp '\(columns[1])'")
                    continue
                }
                
                let event = DoseEvent(
                    eventType: eventType,
                    occurredAtUTC: occurredAt,
                    details: columns[2].isEmpty ? nil : columns[2],
                    deviceTime: columns.count > 3 ? columns[3] : nil
                )
                
                events.append(event)
                
            } catch {
                print("⚠️ Error parsing line \(index + 2): \(error)")
                continue
            }
        }
        
        print("📊 Parsed \(events.count) events from CSV")
        return events
    }
    
    // MARK: - Session Import
    
    /// Load sessions from sessions.csv in the specified folder
    func loadSessions(from folder: URL) async throws -> [DoseSession] {
        let sessionsURL = folder.appendingPathComponent("sessions.csv")
        
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else {
            print("⚠️ sessions.csv not found in \(folder.path)")
            return []
        }
        
        let content = try String(contentsOf: sessionsURL)
        return try parseSessionsCSV(content)
    }
    
    func parseSessionsCSV(_ content: String) throws -> [DoseSession] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }
        
        // Skip header line
        let dataLines = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var sessions: [DoseSession] = []
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for (index, line) in dataLines.enumerated() {
            do {
                let columns = parseCSVLine(line)
                guard columns.count >= 5 else {
                    print("⚠️ Skipping session line \(index + 2): insufficient columns")
                    continue
                }
                
                // Parse required fields
                guard let startedAt = formatter.date(from: columns[0]) else {
                    print("⚠️ Skipping session line \(index + 2): invalid start time '\(columns[0])'")
                    continue
                }
                
                let endedAt = columns[1].isEmpty ? nil : formatter.date(from: columns[1])
                
                let session = DoseSession(
                    startedUTC: startedAt,
                    endedUTC: endedAt,
                    windowTargetMin: Int(columns[2]) ?? 165,
                    windowActualMin: columns[3].isEmpty ? nil : Int(columns[3]),
                    adherenceFlag: columns[4].isEmpty ? nil : columns[4],
                    whoopRecovery: columns.count > 5 && !columns[5].isEmpty ? Int(columns[5]) : nil,
                    avgHR: columns.count > 6 && !columns[6].isEmpty ? Double(columns[6]) : nil,
                    sleepEfficiency: columns.count > 7 && !columns[7].isEmpty ? Double(columns[7]) : nil,
                    notes: columns.count > 8 && !columns[8].isEmpty ? columns[8] : nil
                )
                
                sessions.append(session)
                
            } catch {
                print("⚠️ Error parsing session line \(index + 2): \(error)")
                continue
            }
        }
        
        print("📊 Parsed \(sessions.count) sessions from CSV")
        return sessions
    }
    
    // MARK: - Inventory Import
    
    /// Load inventory from inventory.csv in the specified folder
    func loadInventory(from folder: URL) async throws -> [InventorySnapshot] {
        let inventoryURL = folder.appendingPathComponent("inventory.csv")
        
        guard FileManager.default.fileExists(atPath: inventoryURL.path) else {
            print("⚠️ inventory.csv not found in \(folder.path)")
            return []
        }
        
        let content = try String(contentsOf: inventoryURL)
        return try parseInventoryCSV(content)
    }
    
    func parseInventoryCSV(_ content: String) throws -> [InventorySnapshot] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }
        
        // Skip header line
        let dataLines = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var snapshots: [InventorySnapshot] = []
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for (index, line) in dataLines.enumerated() {
            do {
                let columns = parseCSVLine(line)
                guard columns.count >= 4 else {
                    print("⚠️ Skipping inventory line \(index + 2): insufficient columns")
                    continue
                }
                
                // Parse timestamp
                guard let asOf = formatter.date(from: columns[0]) else {
                    print("⚠️ Skipping inventory line \(index + 2): invalid timestamp '\(columns[0])'")
                    continue
                }
                
                let snapshot = InventorySnapshot(
                    asOfUTC: asOf,
                    bottlesRemaining: Int(columns[1]) ?? 0,
                    dosesRemaining: Int(columns[2]) ?? 0,
                    estimatedDaysLeft: columns[3].isEmpty ? nil : Int(columns[3]),
                    nextRefillDate: columns.count > 4 && !columns[4].isEmpty ? formatter.date(from: columns[4]) : nil,
                    notes: columns.count > 5 && !columns[5].isEmpty ? columns[5] : nil
                )
                
                snapshots.append(snapshot)
                
            } catch {
                print("⚠️ Error parsing inventory line \(index + 2): \(error)")
                continue
            }
        }
        
        print("📊 Parsed \(snapshots.count) inventory snapshots from CSV")
        return snapshots
    }
    
    // MARK: - CSV Parsing Utilities
    
    /// Parse a CSV line handling quoted fields and commas
    func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let char = line[i]
            
            if char == "\"" {
                if inQuotes && i < line.index(before: line.endIndex) && line[line.index(after: i)] == "\"" {
                    // Escaped quote
                    current.append("\"")
                    i = line.index(after: i)
                } else {
                    // Toggle quote state
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                // End of field
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
            
            i = line.index(after: i)
        }
        
        // Add final column
        columns.append(current)
        
        return columns
    }
}
