// Views/ThemeSettingsView.swift
import SwiftUI

struct ThemeSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        List {
            Section {
                Toggle("Night Mode after Dose 1", isOn: $themeManager.automaticNightModeEnabled)
                    .accessibilityIdentifier("automatic-night-mode")
                if themeManager.isAutomaticNightActive {
                    Text("Automatic Night Mode is active until Wake by or your final wake-up.")
                        .font(.caption)
                }
            } footer: {
                Text("Uses red/amber Night Mode after Dose 1 is recorded, then restores your chosen appearance at Wake by. Choosing a theme below overrides it for this night. This changes DoseTap only.")
            }
            Section {
                ForEach(AppTheme.allCases) { theme in
                    ThemeRow(
                        theme: theme,
                        isSelected: themeManager.currentTheme == theme,
                        action: { themeManager.applyTheme(theme) }
                    )
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Night Mode uses red/amber tones to reduce blue light exposure, helping protect your natural sleep cycle.")
                    .font(.caption)
            }
        }
        .navigationTitle("Theme")
        .environment(\.colorScheme, themeManager.currentTheme == .light ? .light : .dark)
        .preferredColorScheme(themeManager.currentTheme == .light ? .light : .dark)
        .themedBackground(themeManager.currentTheme)
    }
}

struct ThemeRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: theme.icon)
                    .font(.title2)
                    .foregroundColor(theme.accentColor)
                    .frame(width: 32)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(theme.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(theme.accentColor)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
}
