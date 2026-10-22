import Foundation

enum DataResetPresentation {
    static let warningKey = "data_reset_cleanup_warning"
    static let cleanupWarning = "Local records and settings were cleared, but alarm cleanup could not be verified. Check iOS alarms and notifications before relying on them."

    @MainActor
    static func finishCleanup(repository: SessionRepository, generation: UInt,
                              verifyAlarms: () async -> Bool, defaults: UserDefaults) async {
        guard repository.dataResetGeneration == generation,
              repository.activeSessionId == nil else { return }
        let verified = await verifyAlarms()
        guard !verified, repository.dataResetGeneration == generation,
              repository.activeSessionId == nil else { return }
        defaults.set(cleanupWarning, forKey: warningKey)
    }
}

