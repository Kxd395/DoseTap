#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Error and warning UI components for DoseTap
/// Provides consistent error alerts and warning banners with accessibility support
@available(iOS 15.0, *)
struct ErrorDisplayView: View {
    @ObservedObject var errorHandler: ErrorHandler
    
    var body: some View {
        ZStack {
            // Warning banner overlay
            if errorHandler.showWarningBanner, let warning = errorHandler.currentWarning {
                VStack {
                    WarningBanner(warning: warning) {
                        errorHandler.dismissWarning()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: errorHandler.showWarningBanner)
                    
                    Spacer()
                }
                .zIndex(1)
            }
        }
        .alert("Error", isPresented: $errorHandler.showErrorAlert) {
            ErrorAlert(error: errorHandler.currentError) {
                errorHandler.clearAll()
            }
        }
    }
}

/// Warning banner that appears at the top of the screen
@available(iOS 15.0, *)
struct WarningBanner: View {
    let warning: DoseTapWarning
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Warning icon
            Image(systemName: iconName)
                .foregroundColor(warning.severity.color)
                .font(.headline)
                .accessibilityHidden(true)
            
            // Warning message
            Text(warning.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .accessibilityLabel("Dismiss warning")
            .accessibilityHint("Closes this warning message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: \(warning.message)")
        .accessibilityHint("Swipe up to dismiss")
        .onTapGesture {
            onDismiss()
        }
    }
    
    private var iconName: String {
        switch warning.severity {
        case .info:
            return "info.circle.fill"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .high:
            return "exclamationmark.octagon.fill"
        }
    }
}

/// Error alert content with action buttons
@available(iOS 15.0, *)
struct ErrorAlert: View {
    let error: DoseTapError?
    let onDismiss: () -> Void
    
    var body: some View {
        Group {
            if let error = error {
                VStack(alignment: .leading, spacing: 8) {
                    // Error description
                    Text(error.localizedDescription)
                        .font(.body)
                    
                    // Recovery suggestion if available
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Action buttons
                Button("OK") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                
                // Additional actions based on error type
                switch error {
                case .dose1AlreadyTaken, .dose2AlreadyTaken:
                    Button("View History") {
                        // Navigate to history view
                        onDismiss()
                    }
                    
                case .dose2TooEarly:
                    Button("Take Anyway") {
                        // Allow user to override
                        onDismiss()
                    }
                    
                case .networkUnavailable:
                    Button("Retry") {
                        // Retry the action
                        onDismiss()
                    }
                    
                default:
                    EmptyView()
                }
            } else {
                Button("OK") {
                    onDismiss()
                }
            }
        }
    }
}

/// Inline error display for forms and inputs
@available(iOS 15.0, *)
struct InlineErrorView: View {
    let error: DoseTapError?
    
    var body: some View {
        if let error = error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .accessibilityHidden(true)
                
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(error.localizedDescription)")
        }
    }
}

/// Loading state with error handling
@available(iOS 15.0, *)
struct LoadingStateView: View {
    let isLoading: Bool
    let error: DoseTapError?
    let onRetry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle())
                
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if let error = error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                        .accessibilityHidden(true)
                    
                    Text(error.localizedDescription)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    if let onRetry = onRetry {
                        Button("Try Again") {
                            onRetry()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
    
    private var accessibilityDescription: String {
        if isLoading {
            return "Loading content"
        } else if let error = error {
            return "Error: \(error.localizedDescription). \(error.recoverySuggestion ?? "")"
        } else {
            return ""
        }
    }
}

/// Empty state with helpful messaging
@available(iOS 15.0, *)
struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - Preview Helpers

@available(iOS 15.0, *)
struct ErrorDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Warning banner preview
            VStack {
                WarningBanner(warning: .windowClosingSoon(300)) {
                    // Preview action
                }
                Spacer()
            }
            .previewDisplayName("Warning Banner")
            
            // Error alert preview
            VStack {
                Text("Main Content")
                Spacer()
            }
            .alert("Error", isPresented: .constant(true)) {
                ErrorAlert(error: .dose1AlreadyTaken(at: Date())) {
                    // Preview action
                }
            }
            .previewDisplayName("Error Alert")
            
            // Loading state preview
            LoadingStateView(
                isLoading: false,
                error: .networkUnavailable,
                onRetry: {}
            )
            .previewDisplayName("Loading Error")
            
            // Empty state preview
            EmptyStateView(
                title: "No Doses Logged",
                message: "Start tracking your doses by taking your first dose of the day.",
                actionTitle: "Take First Dose",
                action: {}
            )
            .previewDisplayName("Empty State")
        }
    }
}
