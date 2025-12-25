import Foundation
import SwiftUI

/// Weekly Planner for optimizing XYWAV dose timing
/// Generates 7-day plans using discrete intervals: 165, 180, 195, 210, 225 minutes
/// Plans are based on TTFW baseline and user's sleep patterns
@MainActor
final class WeeklyPlanner: ObservableObject {
    
    static let shared = WeeklyPlanner()
    
    // MARK: - Valid Intervals (SSOT)
    
    /// Valid target intervals in minutes per SSOT spec
    static let validIntervals: [Int] = [165, 180, 195, 210, 225]
    
    /// Minimum interval (window opens at 150, first valid target is 165)
    static let minimumInterval: Int = 165
    
    /// Maximum interval (hard stop at 240, last comfortable target is 225)
    static let maximumInterval: Int = 225
    
    // MARK: - Published State
    
    @Published var currentPlan: WeeklyPlan?
    @Published var isGenerating: Bool = false
    @Published var lastError: String?
    
    // MARK: - Data Types
    
    struct WeeklyPlan: Identifiable, Codable {
        let id: UUID
        let generatedAt: Date
        let baselineMinutes: Double?
        let days: [DayPlan]
        let rationale: String
        
        init(id: UUID = UUID(), generatedAt: Date = Date(), baselineMinutes: Double?, days: [DayPlan], rationale: String) {
            self.id = id
            self.generatedAt = generatedAt
            self.baselineMinutes = baselineMinutes
            self.days = days
            self.rationale = rationale
        }
    }
    
    struct DayPlan: Identifiable, Codable {
        let id: UUID
        let dayOfWeek: Int  // 1 = Sunday, 7 = Saturday
        let dayName: String
        let targetIntervalMinutes: Int
        let reasoning: String
        let isWeekend: Bool
        
        init(id: UUID = UUID(), dayOfWeek: Int, targetIntervalMinutes: Int, reasoning: String) {
            self.id = id
            self.dayOfWeek = dayOfWeek
            self.dayName = Self.dayNameFor(dayOfWeek)
            self.targetIntervalMinutes = targetIntervalMinutes
            self.reasoning = reasoning
            self.isWeekend = dayOfWeek == 1 || dayOfWeek == 7
        }
        
        private static func dayNameFor(_ dayOfWeek: Int) -> String {
            switch dayOfWeek {
            case 1: return "Sunday"
            case 2: return "Monday"
            case 3: return "Tuesday"
            case 4: return "Wednesday"
            case 5: return "Thursday"
            case 6: return "Friday"
            case 7: return "Saturday"
            default: return "Unknown"
            }
        }
    }
    
    enum PlanStrategy {
        case consistent      // Same interval every day
        case weekendAdjusted // Longer on weekends
        case gradual         // Gradually increase/decrease
        case baseline        // Match TTFW baseline
    }
    
    // MARK: - Plan Generation
    
    /// Generate a weekly plan based on TTFW baseline and preferences
    /// - Parameters:
    ///   - baseline: TTFW baseline in minutes (from HealthKitService)
    ///   - strategy: Planning strategy
    ///   - currentTarget: User's current default target
    func generatePlan(
        baseline: Double?,
        strategy: PlanStrategy = .baseline,
        currentTarget: Int = 165
    ) -> WeeklyPlan {
        isGenerating = true
        defer { isGenerating = false }
        
        let days: [DayPlan]
        let rationale: String
        
        switch strategy {
        case .consistent:
            let target = nearestValidInterval(currentTarget)
            days = (1...7).map { day in
                DayPlan(
                    dayOfWeek: day,
                    targetIntervalMinutes: target,
                    reasoning: "Consistent \(target) min interval for stable sleep rhythm"
                )
            }
            rationale = "Consistent timing helps establish a regular sleep pattern. Your body will adapt to waking at the same interval each night."
            
        case .weekendAdjusted:
            let weekdayTarget = nearestValidInterval(currentTarget)
            let weekendTarget = min(weekdayTarget + 30, Self.maximumInterval)
            days = (1...7).map { day in
                let isWeekend = day == 1 || day == 7
                return DayPlan(
                    dayOfWeek: day,
                    targetIntervalMinutes: isWeekend ? weekendTarget : weekdayTarget,
                    reasoning: isWeekend 
                        ? "Extended \(weekendTarget) min for weekend sleep-in"
                        : "Standard \(weekdayTarget) min for weekday schedule"
                )
            }
            rationale = "Weekends allow for slightly longer sleep intervals while weekdays maintain your work schedule alignment."
            
        case .gradual:
            let target = nearestValidInterval(currentTarget)
            let steps = [target, target, target + 15, target + 15, target + 15, target, target]
            days = (1...7).map { day in
                let stepTarget = min(steps[day - 1], Self.maximumInterval)
                return DayPlan(
                    dayOfWeek: day,
                    targetIntervalMinutes: stepTarget,
                    reasoning: day >= 3 && day <= 5 
                        ? "Mid-week extension to \(stepTarget) min"
                        : "Start/end week at \(stepTarget) min"
                )
            }
            rationale = "Gradual adjustment through the week helps your body adapt without drastic changes."
            
        case .baseline:
            if let baseline = baseline {
                let baseTarget = nearestValidInterval(Int(baseline))
                // Adjust slightly based on day - weekends can be longer
                days = (1...7).map { day in
                    let isWeekend = day == 1 || day == 7
                    let target = isWeekend 
                        ? min(baseTarget + 15, Self.maximumInterval)
                        : baseTarget
                    return DayPlan(
                        dayOfWeek: day,
                        targetIntervalMinutes: target,
                        reasoning: "Based on your \(Int(baseline)) min natural wake pattern"
                            + (isWeekend ? " (+15 min weekend)" : "")
                    )
                }
                rationale = "Plan optimized for your natural \(Int(baseline))-minute Time to First Wake (TTFW) baseline from sleep data."
            } else {
                // No baseline - use default with gentle progression
                days = (1...7).map { day in
                    DayPlan(
                        dayOfWeek: day,
                        targetIntervalMinutes: 165,
                        reasoning: "Default 165 min - track sleep to personalize"
                    )
                }
                rationale = "Default plan using 165-minute interval. Connect Apple Health to get personalized recommendations based on your sleep patterns."
            }
        }
        
        let plan = WeeklyPlan(
            baselineMinutes: baseline,
            days: days,
            rationale: rationale
        )
        
        currentPlan = plan
        savePlan(plan)
        
        return plan
    }
    
    /// Find the nearest valid interval to a target value
    func nearestValidInterval(_ target: Int) -> Int {
        Self.validIntervals.min(by: { abs($0 - target) < abs($1 - target) }) ?? 165
    }
    
    /// Get today's planned interval
    func todayTarget() -> Int? {
        guard let plan = currentPlan else { return nil }
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        return plan.days.first { $0.dayOfWeek == dayOfWeek }?.targetIntervalMinutes
    }
    
    /// Get plan for a specific day
    func planFor(dayOfWeek: Int) -> DayPlan? {
        currentPlan?.days.first { $0.dayOfWeek == dayOfWeek }
    }
    
    // MARK: - Persistence
    
    private let planKey = "weeklyPlanner_currentPlan"
    
    private func savePlan(_ plan: WeeklyPlan) {
        if let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: planKey)
        }
    }
    
    func loadSavedPlan() {
        if let data = UserDefaults.standard.data(forKey: planKey),
           let plan = try? JSONDecoder().decode(WeeklyPlan.self, from: data) {
            currentPlan = plan
        }
    }
    
    /// Check if plan needs regeneration (older than 7 days)
    func planNeedsRefresh() -> Bool {
        guard let plan = currentPlan else { return true }
        let daysSinceGeneration = Calendar.current.dateComponents(
            [.day], from: plan.generatedAt, to: Date()
        ).day ?? 0
        return daysSinceGeneration >= 7
    }
}

// MARK: - Weekly Planner View

struct WeeklyPlannerView: View {
    @StateObject private var planner = WeeklyPlanner.shared
    @StateObject private var healthKit = HealthKitService.shared
    @State private var selectedStrategy: WeeklyPlanner.PlanStrategy = .baseline
    @State private var showingStrategyPicker = false
    
    var body: some View {
        List {
            // Current Plan Section
            if let plan = planner.currentPlan {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.blue)
                            Text("Your Weekly Plan")
                                .font(.headline)
                        }
                        
                        Text(plan.rationale)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let baseline = plan.baselineMinutes {
                            Label("Based on \(Int(baseline)) min TTFW", systemImage: "moon.zzz.fill")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("Active Plan")
                        Spacer()
                        Text("Generated \(plan.generatedAt, style: .relative) ago")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Daily Targets
                Section {
                    ForEach(plan.days) { day in
                        DayPlanRow(day: day, isToday: isToday(day.dayOfWeek))
                    }
                } header: {
                    Label("Daily Targets", systemImage: "list.bullet")
                }
            }
            
            // Generate New Plan Section
            Section {
                Button {
                    showingStrategyPicker = true
                } label: {
                    Label(planner.currentPlan == nil ? "Generate Plan" : "Regenerate Plan",
                          systemImage: "wand.and.stars")
                }
                
                if healthKit.ttfwBaseline == nil {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Connect Apple Health for personalized plans")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("Actions", systemImage: "sparkles")
            }
            
            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Valid Intervals", systemImage: "clock.fill")
                        .font(.subheadline.bold())
                    
                    HStack(spacing: 8) {
                        ForEach(WeeklyPlanner.validIntervals, id: \.self) { interval in
                            Text("\(interval)")
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("Intervals are aligned with XYWAV's 150-240 min window")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Weekly Planner")
        .onAppear {
            planner.loadSavedPlan()
        }
        .confirmationDialog("Choose Strategy", isPresented: $showingStrategyPicker) {
            Button("Match Sleep Pattern") {
                _ = planner.generatePlan(baseline: healthKit.ttfwBaseline, strategy: .baseline)
            }
            Button("Consistent Daily") {
                _ = planner.generatePlan(baseline: healthKit.ttfwBaseline, strategy: .consistent)
            }
            Button("Weekend Adjusted") {
                _ = planner.generatePlan(baseline: healthKit.ttfwBaseline, strategy: .weekendAdjusted)
            }
            Button("Gradual Mid-Week") {
                _ = planner.generatePlan(baseline: healthKit.ttfwBaseline, strategy: .gradual)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private func isToday(_ dayOfWeek: Int) -> Bool {
        Calendar.current.component(.weekday, from: Date()) == dayOfWeek
    }
}

struct DayPlanRow: View {
    let day: WeeklyPlanner.DayPlan
    let isToday: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Text(day.dayName)
                        .font(.subheadline)
                        .fontWeight(isToday ? .bold : .regular)
                    if isToday {
                        Text("TODAY")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    if day.isWeekend {
                        Image(systemName: "moon.fill")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
                Text(day.reasoning)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(day.targetIntervalMinutes) min")
                .font(.title3.bold())
                .foregroundColor(isToday ? .blue : .primary)
        }
        .padding(.vertical, 4)
        .background(isToday ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Compact Plan Summary (for Tonight view)

struct CompactPlanSummary: View {
    @StateObject private var planner = WeeklyPlanner.shared
    
    var body: some View {
        if let todayTarget = planner.todayTarget() {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.blue)
                Text("Today's Target:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(todayTarget) min")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
