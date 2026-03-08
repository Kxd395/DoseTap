import SwiftUI

// MARK: - Quick Event Panel (Compact)
struct QuickEventPanel: View {
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var settings = UserSettingsManager.shared
    
    // Get quick events (max 15)
    private var quickEvents: [(name: String, icon: String, color: Color)] {
        let all = settings.quickLogButtons.map { ($0.name, $0.icon, $0.color) }
        return Array(all.prefix(15))
    }
    
    /// Dynamic grid layout based on icon count:
    /// - 9 icons = 3x3
    /// - 10 icons = 5x2
    /// - 12 icons = 4x3
    /// - 11-15 icons = 5x3
    private var columnsForCount: Int {
        let count = quickEvents.count
        switch count {
        case 0...3: return count  // Single row
        case 4: return 4          // 4x1
        case 5: return 5          // 5x1
        case 6: return 3          // 3x2
        case 7...8: return 4      // 4x2
        case 9: return 3          // 3x3
        case 10: return 5         // 5x2
        case 11...12: return 4    // 4x3
        default: return 5         // 5x3 for 13-15
        }
    }
    
    // Split into rows based on dynamic column count
    private var eventRows: [[(name: String, icon: String, color: Color)]] {
        let cols = columnsForCount
        var rows: [[(name: String, icon: String, color: Color)]] = []
        var currentRow: [(name: String, icon: String, color: Color)] = []
        
        for (index, event) in quickEvents.enumerated() {
            currentRow.append(event)
            if currentRow.count == cols || index == quickEvents.count - 1 {
                rows.append(currentRow)
                currentRow = []
            }
        }
        return rows
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quick Log")
                    .font(.caption.bold())
                Spacer()
                if !eventLogger.events.isEmpty {
                    Text("\(eventLogger.events.count) tonight")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Display rows with dynamic column count
            ForEach(0..<eventRows.count, id: \.self) { rowIndex in
                HStack(spacing: 4) {
                    ForEach(eventRows[rowIndex], id: \.name) { event in
                        quickButton(for: event)
                    }
                    // Fill remaining space if row is incomplete
                    let cols = columnsForCount
                    if eventRows[rowIndex].count < cols {
                        ForEach(0..<(cols - eventRows[rowIndex].count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
    }
    
    @ViewBuilder
    private func quickButton(for event: (name: String, icon: String, color: Color)) -> some View {
        let cooldown = settings.cooldown(for: event.name)
        CompactQuickButton(
            name: event.name,
            icon: event.icon,
            color: event.color,
            cooldownSeconds: cooldown,
            cooldownEnd: eventLogger.cooldownEnd(for: event.name),
            lastLogTime: eventLogger.lastEventTime(for: event.name),
            onTap: {
                eventLogger.logEvent(name: event.name, color: event.color, cooldownSeconds: cooldown)
            }
        )
    }
}

// MARK: - Compact Quick Event Button
struct CompactQuickButton: View {
    let name: String
    let icon: String
    let color: Color
    let cooldownSeconds: TimeInterval
    let cooldownEnd: Date?
    let lastLogTime: Date?
    let onTap: () -> Void
    
    @State private var progress: CGFloat = 1.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var isOnCooldown: Bool {
        guard let end = cooldownEnd else { return false }
        return Date() < end
    }
    
    /// P3-4: Relative "time since" badge text
    private var timeSinceBadge: String? {
        guard !isOnCooldown else { return nil }
        return EventLogger.relativeBadge(since: lastLogTime)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isOnCooldown ? 0.2 : 0.15))
                        .frame(width: 44, height: 44)  // Minimum 44pt tap target
                    
                    if isOnCooldown {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(color.opacity(0.5), lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                    }
                    
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(isOnCooldown ? color.opacity(0.4) : color)
                }
                
                Text(name)
                    .font(.system(size: 9))
                    .foregroundColor(isOnCooldown ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // P3-4: "time since" badge
                if let badge = timeSinceBadge {
                    Text(badge)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(color.opacity(0.7))
                        .lineLimit(1)
                } else {
                    // Invisible spacer to maintain consistent layout
                    Text(" ")
                        .font(.system(size: 8))
                }
            }
        }
        .disabled(isOnCooldown)
        .frame(maxWidth: .infinity)
        // Accessibility
        .accessibilityLabel("\(name) event button")
        .accessibilityHint(isOnCooldown ? "Button on cooldown. Wait to log again." : "Double tap to log \(name) event")
        .accessibilityAddTraits(isOnCooldown ? .isButton : [.isButton])
        .onReceive(timer) { _ in
            updateProgress()
        }
    }
    
    private func updateProgress() {
        guard let end = cooldownEnd else { progress = 1.0; return }
        let now = Date()
        if now >= end {
            progress = 1.0
        } else {
            let remaining = end.timeIntervalSince(now)
            progress = 1.0 - CGFloat(remaining / cooldownSeconds)
        }
    }
}

// MARK: - Wake Up & End Session Button
struct WakeUpButton: View {
    @ObservedObject var eventLogger: EventLogger
    @Binding var showMorningCheckIn: Bool
    @ObservedObject var settings = UserSettingsManager.shared
    private let sessionRepo = SessionRepository.shared
    @State private var showConfirmation = false
    
    // Wake Up cooldown (1 hour per SSOT)
    private let cooldownSeconds: TimeInterval = 3600

    private var hasDoseOrEventContext: Bool {
        sessionRepo.dose1Time != nil || !eventLogger.events.isEmpty
    }

    private var confirmationTitle: String {
        hasDoseOrEventContext ? "End Sleep Session?" : "Start Morning Check-In?"
    }

    private var confirmationMessage: String {
        if hasDoseOrEventContext {
            return "This will log your wake time and open the morning check-in."
        }
        return "No Dose 1 or sleep events are logged yet. Continue if you need to backfill missed doses in the morning check-in."
    }

    private var confirmationButtonTitle: String {
        hasDoseOrEventContext ? "Wake Up & Start Check-In" : "Start Check-In Anyway"
    }
    
    var body: some View {
        Button {
            // Show confirmation dialog first
            showConfirmation = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake Up & End Session")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Complete your morning check-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.yellow.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .disabled(isOnCooldown)
        .opacity(isOnCooldown ? 0.5 : 1.0)
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button(confirmationButtonTitle) {
                logWakeAndShowCheckIn()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(confirmationMessage)
        }
    }
    
    private func logWakeAndShowCheckIn() {
        // Log the Wake Up event for UI cooldown only (sessionRepo handles persistence)
        eventLogger.logEvent(
            name: "Wake Up",
            color: .yellow,
            cooldownSeconds: cooldownSeconds,
            persist: false
        )

        // Persist wake event + mark session finalizing
        sessionRepo.setWakeFinalTime(Date())
        
        // Show check-in immediately (slight delay to let confirmation dismiss)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMorningCheckIn = true
        }
    }
    
    private var isOnCooldown: Bool {
        guard let end = eventLogger.cooldownEnd(for: "Wake Up") else { return false }
        return Date() < end
    }
}
