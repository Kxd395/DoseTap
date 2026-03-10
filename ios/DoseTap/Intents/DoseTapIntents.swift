// DoseTapIntents.swift — P2-2 Siri Shortcuts / AppIntents
// Requires iOS 16+ AppIntents framework.
import AppIntents
import Foundation
import os.log

private let intentLog = Logger(subsystem: "com.dosetap.app", category: "AppIntents")

// MARK: - Check Dose Status Intent

struct CheckDoseStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Dose Status"
    static var description = IntentDescription("Check your current XYWAV dosing status and remaining window time.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = SessionRepository.shared
        let d1 = repo.dose1Time
        let d2 = repo.dose2Time

        if d1 == nil {
            return .result(dialog: "No dose taken tonight. Dose 1 hasn't been logged yet.")
        }

        if let d2 = d2 {
            let interval = Int(d2.timeIntervalSince(d1!) / 60)
            return .result(dialog: "Both doses taken. Interval was \(interval) minutes.")
        }

        // Dose 1 taken, dose 2 pending
        let elapsed = Int(Date().timeIntervalSince(d1!) / 60)
        let windowOpen = max(0, 150 - elapsed)
        let windowClose = max(0, 240 - elapsed)

        if windowOpen > 0 {
            return .result(dialog: "Dose 1 taken \(elapsed)m ago. Window opens in \(windowOpen) minutes.")
        } else {
            return .result(dialog: "Dose window is OPEN. \(windowClose) minutes remaining. Time for Dose 2!")
        }
    }
}

// MARK: - Sleep Event Type Enum

enum SleepEventTypeEnum: String, AppEnum {
    case bathroom = "bathroom"
    case anxiety = "anxiety"
    case briefWake = "brief_wake"
    case lightsOut = "lights_out"
    case wakeFinal = "wake_final"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep Event Type"
    static var caseDisplayRepresentations: [SleepEventTypeEnum: DisplayRepresentation] = [
        .bathroom: "Bathroom",
        .anxiety: "Anxiety",
        .briefWake: "Brief Wake",
        .lightsOut: "Lights Out",
        .wakeFinal: "Wake Final"
    ]
}

// MARK: - Log Event Intent

struct LogSleepEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Sleep Event"
    static var description = IntentDescription("Log a sleep event like bathroom, anxiety, or brief wake.")

    @Parameter(title: "Event Type")
    var eventType: SleepEventTypeEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = SessionRepository.shared
        repo.logSleepEvent(eventType: eventType.rawValue)
        intentLog.info("Siri logged event: \(eventType.rawValue, privacy: .public)")
        return .result(dialog: "Logged \(eventType.rawValue) event.")
    }
}

// MARK: - Shortcuts Provider

struct DoseTapShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckDoseStatusIntent(),
            phrases: [
                "Check my dose status in \(.applicationName)",
                "What's my dose status in \(.applicationName)",
                "How's my dosing tonight in \(.applicationName)"
            ],
            shortTitle: "Dose Status",
            systemImageName: "pills.fill"
        )
        AppShortcut(
            intent: LogSleepEventIntent(),
            phrases: [
                "Log a sleep event in \(.applicationName)",
                "Log \(\.$eventType) in \(.applicationName)"
            ],
            shortTitle: "Log Event",
            systemImageName: "list.bullet"
        )
    }
}
