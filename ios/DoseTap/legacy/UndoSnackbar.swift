import SwiftUI

@available(iOS 15.0, *)
struct UndoSnackbar: View {
    let action: UndoableAction
    let remainingTime: TimeInterval
    let onUndo: () async -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityContrast) private var accessibilityContrast
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Action: \(action.actionDescription)")
                    .font(bodyFont)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)
                
                Text(String(format: "%.1fs to undo", remainingTime))
                    .font(captionFont)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Undo") {
                Task { await onUndo() }
            }
            .buttonStyle(.bordered)
            .font(bodyFont)
            .foregroundColor(undoButtonColor)
            .accessibilityLabel("Undo last action")
            .accessibilityHint("Double tap to undo \(action.actionDescription)")
            
            Button(action: onDismiss) {
                if differentiateWithoutColor {
                    Text("✕")
                        .font(captionFont)
                        .fontWeight(.bold)
                } else {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(textColor)
            .accessibilityLabel("Dismiss undo notification")
            .accessibilityHint("Double tap to dismiss this undo option")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: differentiateWithoutColor ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: reduceTransparency ? 0 : 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Undo available: \(action.actionDescription), \(Int(remainingTime)) seconds remaining")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
    
    private var bodyFont: Font {
        if #available(iOS 13.0, *) {
            return AccessibilitySupport.bodyFont
        } else {
            return .body
        }
    }
    
    private var captionFont: Font {
        if #available(iOS 13.0, *) {
            return AccessibilitySupport.captionFont
        } else {
            return .caption
        }
    }
    
    private var textColor: Color {
        if #available(iOS 13.0, *) {
            return AccessibilitySupport.primaryButtonColor(
                colorScheme: colorScheme,
                accessibilityContrast: accessibilityContrast
            )
        } else {
            return .primary
        }
    }
    
    private var undoButtonColor: Color {
        if #available(iOS 13.0, *) {
            return AccessibilitySupport.primaryButtonColor(
                colorScheme: colorScheme,
                accessibilityContrast: accessibilityContrast
            )
        } else {
            return .blue
        }
    }
    
    private var backgroundColor: Color {
        if #available(iOS 13.0, *) {
            return AccessibilitySupport.backgroundColor(
                colorScheme: colorScheme,
                accessibilityContrast: accessibilityContrast
            )
        } else {
            // Fallback for iOS 12 and earlier (though iOS 15 is required for this component)
            return Color.white
        }
    }
    
    private var borderColor: Color {
        if differentiateWithoutColor {
            return textColor
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

@available(iOS 15.0, *)
struct UndoOverlay: View {
    @ObservedObject var undoManager: DoseTap.UndoManager
    
    var body: some View {
        if let action = undoManager.undoableAction {
            VStack {
                Spacer()
                
                UndoSnackbar(
                    action: action,
                    remainingTime: undoManager.remainingTime,
                    onUndo: {
                        let success = await undoManager.performUndo()
                        if !success {
                            // Could show error message here
                            print("Undo failed")
                        }
                    },
                    onDismiss: {
                        undoManager.clearUndo()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 50)
                .adaptiveTransition(.move(edge: .bottom).combined(with: .opacity))
            }
            .adaptiveAnimation(.easeInOut(duration: 0.3), value: undoManager.undoableAction?.eventId)
        }
    }
}
