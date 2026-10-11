import Foundation

enum DataResetPresentation {
    static let warningKey = "data_reset_cleanup_warning"
    static let cleanupWarning = "Local records and settings were cleared, but alarm cleanup could not be verified. Check iOS alarms and notifications before relying on them."

    @MainActor
    static func finishCleanup(
        repository: SessionRepository,
        generation: UInt,
        daytimeCleanup: Task<Bool, Never>,
        verifyAlarms: () async -> Bool,
        defaults: UserDefaults
    ) async {
        let daytimeVerified = await daytimeCleanup.value
        guard repository.dataResetGeneration == generation else { return }
        var alarmsVerified = true
        if repository.activeSessionId == nil {
            alarmsVerified = await verifyAlarms()
            if repository.activeSessionId != nil { alarmsVerified = true }
        }
        guard !alarmsVerified || !daytimeVerified,
              repository.dataResetGeneration == generation else { return }
        defaults.set(cleanupWarning, forKey: warningKey)
    }
}
