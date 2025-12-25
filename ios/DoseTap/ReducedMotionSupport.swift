import SwiftUI

// MARK: - Reduced Motion View Modifier

/// View modifier that conditionally applies animation based on reduced motion preferences
struct ConditionalAnimationModifier<V: Equatable>: ViewModifier {
    let value: V
    let animation: Animation
    
    @ObservedObject private var settings = UserSettingsManager.shared
    
    func body(content: Content) -> some View {
        if settings.shouldReduceMotion {
            // No animation when reduced motion is enabled
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}

// MARK: - View Extensions for Reduced Motion

extension View {
    /// Applies animation only if reduced motion is not enabled
    /// - Parameters:
    ///   - animation: The animation to apply
    ///   - value: The value to watch for changes
    /// - Returns: Modified view with conditional animation
    func accessibleAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ConditionalAnimationModifier(value: value, animation: animation))
    }
    
    /// Conditionally applies a transition based on reduced motion preference
    /// - Parameter transition: The transition to apply when motion is allowed
    /// - Returns: Modified view with conditional transition
    @ViewBuilder
    func accessibleTransition(_ transition: AnyTransition) -> some View {
        if UserSettingsManager.shared.shouldReduceMotion {
            self.transition(.opacity)
        } else {
            self.transition(transition)
        }
    }
    
    /// Applies withAnimation only when reduced motion is disabled
    /// Use: `withAccessibleAnimation { /* state change */ }`
    func withAccessibleAnimation(_ body: () -> Void) {
        if UserSettingsManager.shared.shouldReduceMotion {
            body()
        } else {
            withAnimation { body() }
        }
    }
}

// MARK: - Accessible Animation Function

/// Executes a state change with animation only if reduced motion is disabled
/// - Parameters:
///   - animation: The animation to use (default: .default)
///   - body: The closure containing state changes
func withAccessibleAnimation(_ animation: Animation = .default, _ body: () -> Void) {
    if UserSettingsManager.shared.shouldReduceMotion {
        body()
    } else {
        withAnimation(animation) {
            body()
        }
    }
}

/// Executes an async state change with animation only if reduced motion is disabled
@MainActor
func withAccessibleAnimation<Result>(_ animation: Animation = .default, _ body: () async throws -> Result) async rethrows -> Result {
    if UserSettingsManager.shared.shouldReduceMotion {
        return try await body()
    } else {
        return try await withAnimation(animation) {
            // Note: withAnimation doesn't support async, so we use this pattern
            return try body()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ReducedMotionDemo_Previews: PreviewProvider {
    struct DemoView: View {
        @State private var isExpanded = false
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Reduced Motion: \(UserSettingsManager.shared.shouldReduceMotion ? "ON" : "OFF")")
                    .font(.headline)
                
                Button("Toggle") {
                    withAccessibleAnimation {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue)
                    .frame(width: isExpanded ? 200 : 100, height: isExpanded ? 200 : 100)
                    .accessibleAnimation(.spring(response: 0.5), value: isExpanded)
                
                Text("The rectangle above will animate smoothly when Reduce Motion is OFF, and snap instantly when ON.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
    
    static var previews: some View {
        DemoView()
    }
}
#endif
