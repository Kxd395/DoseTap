// Views/ThemeToggleButton.swift
import SwiftUI

/// Compact theme toggle button for quick access on any screen
struct ThemeToggleButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showPicker = false
    
    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: themeManager.currentTheme.icon)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(themeManager.currentTheme.accentColor)
            .frame(width: 36, height: 36)
            .background(themeManager.currentTheme.cardBackground)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(themeManager.currentTheme.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .confirmationDialog("Theme", isPresented: $showPicker, titleVisibility: .hidden) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        themeManager.applyTheme(theme)
                    }
                } label: {
                    HStack {
                        Image(systemName: theme.icon)
                        Text(theme.rawValue)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Alternative: Segmented control style for inline placement
struct ThemeSegmentedControl: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        themeManager.applyTheme(theme)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: theme.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(theme == .night ? "Night" : theme.rawValue)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundColor(
                        themeManager.currentTheme == theme
                            ? themeManager.currentTheme.buttonText
                            : themeManager.currentTheme.secondaryText
                    )
                    .background(
                        themeManager.currentTheme == theme
                            ? themeManager.currentTheme.buttonBackground
                            : themeManager.currentTheme.cardBackground
                    )
                    .cornerRadius(8)
                }
            }
        }
        .padding(4)
        .background(themeManager.currentTheme.secondaryBackground)
        .cornerRadius(10)
    }
}

/// Alternative: Quick cycle button (tap to cycle through themes)
struct ThemeCycleButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button {
            cycleTheme()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: themeManager.currentTheme.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(shortLabel)
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(themeManager.currentTheme.buttonText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(themeManager.currentTheme.buttonBackground.opacity(0.8))
            .cornerRadius(20)
        }
    }
    
    private var shortLabel: String {
        switch themeManager.currentTheme {
        case .light: return "Light"
        case .dark: return "Dark"
        case .night: return "Night"
        }
    }
    
    private func cycleTheme() {
        withAnimation(.easeInOut(duration: 0.3)) {
            let current = themeManager.currentTheme
            let all = AppTheme.allCases
            guard let index = all.firstIndex(of: current) else { return }
            let nextIndex = (index + 1) % all.count
            themeManager.applyTheme(all[nextIndex])
        }
    }
}

// MARK: - Preview
#if DEBUG
struct ThemeToggleButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ThemeToggleButton()
            ThemeSegmentedControl()
            ThemeCycleButton()
        }
        .padding()
        .environmentObject(ThemeManager.shared)
    }
}
#endif
