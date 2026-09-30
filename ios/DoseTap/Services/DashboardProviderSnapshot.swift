import Foundation
import HealthKit
import DoseCore

/// Model-lifetime snapshot. The successful query window never advances on a failed attempt.
struct DashboardProviderSnapshot<Summary> {
    let values: [String: Summary]
    let window: DashboardReportingWindow
    let queryStart: Date
    let epoch: UUID?
    var failedAttemptAt: Date?
    var isPartial = false

    func matches(timeZone: TimeZone, epoch: UUID?) -> Bool {
        epoch != nil && self.epoch == epoch && window.timeZone == timeZone
    }

    func description(provider: String) -> String {
        let formatter = DateFormatter(); formatter.locale = .current; formatter.timeZone = window.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        let query = "\(provider) successful query: \(formatter.string(from: queryStart)) – \(formatter.string(from: window.healthQueryEnd)) (\(window.timeZone.identifier))."
        let stale = failedAttemptAt.map { " Stale results retained after the failed attempt at \(formatter.string(from: $0))." } ?? ""
        let partial = isPartial ? " This sleep snapshot has unavailable recovery metrics." : ""
        return query + stale + partial
    }
}

enum DashboardProviderFailure {
    static func isCancelled(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static func isTransient(_ error: Error) -> Bool {
        if let url = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable, .dataNotAllowed,
                    .internationalRoamingOff, .callIsActive].contains(url.code)
        }
        if case WHOOPError.httpError(let code) = error { return code == 429 || (500..<600).contains(code) }
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorDatabaseInaccessible.rawValue
    }
}
