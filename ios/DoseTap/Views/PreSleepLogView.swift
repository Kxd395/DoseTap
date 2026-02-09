import SwiftUI

/// Compatibility wrapper that routes all legacy call sites to the canonical V2 flow.
struct PreSleepLogView: View {
    let existingLog: StoredPreSleepLog?
    let onComplete: (PreSleepLogAnswers) throws -> Void
    let onSkip: () throws -> Void

    init(
        existingLog: StoredPreSleepLog? = nil,
        onComplete: @escaping (PreSleepLogAnswers) throws -> Void,
        onSkip: @escaping () throws -> Void
    ) {
        self.existingLog = existingLog
        self.onComplete = onComplete
        self.onSkip = onSkip
    }

    var body: some View {
        PreSleepLogViewV2(
            existingLog: existingLog,
            onComplete: onComplete,
            onSkip: onSkip
        )
    }
}

#Preview {
    PreSleepLogView(
        onComplete: { _ in },
        onSkip: { }
    )
}
