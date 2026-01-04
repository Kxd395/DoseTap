// Views/ThemeSettingsView.swift
import SwiftUI

struct ThemeSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        List {
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
