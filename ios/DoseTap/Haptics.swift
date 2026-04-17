//
//  Haptics.swift
//  DoseTap
//
//  Centralized haptic feedback service.
//  All semantic haptics should go through this enum so that:
//    - User preference (UserSettingsManager.hapticsEnabled) is respected
//    - Styles stay consistent across the app
//    - Generators are prepared to reduce latency
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Semantic haptic feedback for app-level interactions.
/// Always route haptics through this enum rather than instantiating
/// UIImpactFeedbackGenerator / UINotificationFeedbackGenerator directly.
enum Haptics {
    /// Dose taken / session complete — strongest positive confirmation.
    case doseTaken
    /// Warning / destructive confirmation (e.g. hold-to-confirm fires, skip confirmed).
    case warning
    /// Error / failure.
    case error
    /// Medium impact: general action (snooze, log event, event deleted).
    case action
    /// Light impact: subtle UI tap (theme toggle, chip selected).
    case light

    /// Play the haptic, respecting the user's haptics preference.
    func play() {
        #if canImport(UIKit)
        guard UserSettingsManager.shared.hapticsEnabled else { return }
        switch self {
        case .doseTaken:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        case .warning:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.warning)
        case .error:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.error)
        case .action:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            g.impactOccurred()
        case .light:
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            g.impactOccurred()
        }
        #endif
    }
}
