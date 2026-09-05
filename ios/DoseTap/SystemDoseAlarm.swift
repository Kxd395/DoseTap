import Foundation
import AlarmKit
import AppIntents
import SwiftUI

enum SystemDoseAlarmError: LocalizedError {
    case permission, verification, cancelled
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Alarms for DoseTap in iOS Settings, then retry the Dose 2 alarm."
        case .verification: return "iOS did not confirm the Dose 2 system alarm. Retry the alarm."
        case .cancelled: return "The Dose 2 system alarm was cancelled while scheduling."
        }
    }
}

@MainActor
protocol SystemDoseAlarmScheduling: AnyObject {
    var authorizationDescription: String { get }
    func requestAuthorization() async throws
    func schedule(at date: Date) async throws
    func deadline() throws -> Date?
    func cancel() throws
}

enum SystemDoseAlarmFactory {
    static let requestIdentifier = "6D6F7365-7461-4070-9000-000000000002"
    @MainActor static func make() -> (any SystemDoseAlarmScheduling)? {
        if #available(iOS 26.0, *) { return SystemDoseAlarmClient.shared }
        return nil
    }
    @MainActor static func makeTestAlarm() -> (any SystemDoseAlarmScheduling)? {
        if #available(iOS 26.0, *) { return SystemDoseAlarmClient.testAlarm }
        return nil
    }
}

@available(iOS 26.0, *)
struct DoseAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
struct OpenDoseTapAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open DoseTap"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        URLRouter.shared.selectedTab = .tonight
        return .result()
    }
}

/// System delivery is separate from medication intent. No database access here.
@available(iOS 26.0, *)
@MainActor
final class SystemDoseAlarmClient: SystemDoseAlarmScheduling {
    static let shared = SystemDoseAlarmClient()
    static let testAlarm = SystemDoseAlarmClient(id: UUID(uuidString: "6D6F7365-7461-4070-9000-00000000FFFF")!, title: "DoseTap alarm test")
    static let identifier = UUID(uuidString: SystemDoseAlarmFactory.requestIdentifier)!
    private let manager = AlarmManager.shared
    private var generation: UInt = 0
    private let id: UUID
    private let title: LocalizedStringResource

    private init(id: UUID? = nil, title: LocalizedStringResource = "Dose 2 reminder") {
        self.id = id ?? Self.identifier
        self.title = title
    }

    var authorizationDescription: String {
        switch manager.authorizationState {
        case .authorized: return "Allowed — system alarms work while locked, including Silent and Focus."
        case .denied: return "Not allowed — enable Alarms for DoseTap in iOS Settings."
        case .notDetermined: return "Permission needed for locked-phone alarms."
        @unknown default: return "Alarm permission could not be verified."
        }
    }

    func requestAuthorization() async throws {
        if manager.authorizationState == .notDetermined { _ = try await manager.requestAuthorization() }
        guard manager.authorizationState == .authorized else { throw SystemDoseAlarmError.permission }
    }

    func deadline() throws -> Date? {
        guard let alarm = try manager.alarms.first(where: { $0.id == id }),
              case .fixed(let date) = alarm.schedule else { return nil }
        return date
    }

    func schedule(at date: Date) async throws {
        let ticket = generation
        try await requestAuthorization()
        guard ticket == generation else { throw SystemDoseAlarmError.cancelled }
        if try deadline() == date { return }
        if try deadline() != nil { try manager.cancel(id: id) }
        let open = AlarmButton(text: "Open DoseTap", textColor: .white, systemImageName: "arrow.up.right")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: open, secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(title: title,
                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: open, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: DoseAlarmMetadata(), tintColor: .blue)
        let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: .fixed(date), attributes: attributes,
            secondaryIntent: OpenDoseTapAlarmIntent())
        _ = try await manager.schedule(id: id, configuration: configuration)
        guard ticket == generation else {
            try manager.cancel(id: id)
            throw SystemDoseAlarmError.cancelled
        }
        guard try deadline() == date else { throw SystemDoseAlarmError.verification }
    }

    func cancel() throws {
        generation &+= 1
        if try manager.alarms.contains(where: { $0.id == id }) {
            try manager.cancel(id: id)
        }
    }
}
