import SwiftUI

/// Compatibility wrapper that routes all legacy call sites to the canonical V2 flow.
struct MorningCheckInView: View {
    let sessionId: String
    let sessionDate: String
    let onComplete: () -> Void

    init(sessionId: String, sessionDate: String, onComplete: @escaping () -> Void = {}) {
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.onComplete = onComplete
    }

    var body: some View {
        MorningCheckInViewV2(
            sessionId: sessionId,
            sessionDate: sessionDate,
            onComplete: onComplete
        )
    }
}

#Preview {
    MorningCheckInView(sessionId: "preview-session", sessionDate: "2025-01-01")
}
