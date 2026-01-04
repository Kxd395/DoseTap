// Theme/AppTheme.swift
import SwiftUI

/// App-wide theme system: Light, Dark, Night (red light for sleep protection)
enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case night = "Night Mode" // Red light mode - no blue wavelengths
    
    var id: String { rawValue }
    
    // MARK: - Background Colors
    var backgroundColor: Color {
        switch self {
        case .light: return Color(.systemBackground)
        case .dark: return Color(.systemBackground)
        case .night: return Color(red: 0.08, green: 0.0, blue: 0.0) // Very deep red-black
        }
    }
    
    var secondaryBackground: Color {
        switch self {
        case .light: return Color(.secondarySystemBackground)
        case .dark: return Color(.secondarySystemBackground)
        case .night: return Color(red: 0.12, green: 0.02, blue: 0.0) // Slightly lighter red-black
        }
    }
    
    var cardBackground: Color {
        switch self {
        case .light: return Color(.secondarySystemBackground)
        case .dark: return Color(.secondarySystemBackground)
        case .night: return Color(red: 0.15, green: 0.03, blue: 0.0) // Red-tinted card
        }
    }
    
    // MARK: - Text Colors
    var primaryText: Color {
        switch self {
        case .light: return .primary
        case .dark: return .primary
        case .night: return Color(red: 1.0, green: 0.6, blue: 0.4) // Warm amber
        }
    }
    
    var secondaryText: Color {
        switch self {
        case .light: return .secondary
        case .dark: return .secondary
        case .night: return Color(red: 0.9, green: 0.5, blue: 0.3) // Dimmer amber
        }
    }
    
    // MARK: - Accent Colors
    var accentColor: Color {
        switch self {
        case .light: return Color(red: 0.204, green: 0.827, blue: 0.780) // Teal #34D3C7
        case .dark: return Color(red: 0.204, green: 0.827, blue: 0.780) // Teal #34D3C7
        case .night: return Color(red: 0.8, green: 0.2, blue: 0.1) // Deep red
        }
    }
    
    var buttonBackground: Color {
        switch self {
        case .light: return accentColor
        case .dark: return accentColor
        case .night: return Color(red: 0.6, green: 0.15, blue: 0.0) // Dark red
        }
    }
    
    var buttonText: Color {
        switch self {
        case .light: return .white
        case .dark: return .white
        case .night: return Color(red: 1.0, green: 0.7, blue: 0.5) // Light amber
        }
    }
    
    // MARK: - Status Colors
    var successColor: Color {
        switch self {
        case .light: return .green
        case .dark: return .green
        case .night: return Color(red: 0.9, green: 0.6, blue: 0.0) // Amber (no green)
        }
    }
    
    var warningColor: Color {
        switch self {
        case .light: return .orange
        case .dark: return .orange
        case .night: return Color(red: 1.0, green: 0.4, blue: 0.0) // Deep orange
        }
    }
    
    var errorColor: Color {
        switch self {
        case .light: return .red
        case .dark: return .red
        case .night: return Color(red: 0.8, green: 0.2, blue: 0.0) // Pure red
        }
    }
    
    // MARK: - System Color Scheme (for light/dark compatibility)
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .night: return nil // Custom rendering
        }
    }
    
    // MARK: - Description
    var description: String {
        switch self {
        case .light: return "Standard light appearance"
        case .dark: return "Standard dark appearance"
        case .night: return "Red light mode - reduces blue light exposure for better sleep"
        }
    }
    
    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .night: return "bed.double.fill"
        }
    }
}

// MARK: - Theme Manager
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme")
        }
    }
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: "selectedTheme")
        self.currentTheme = AppTheme(rawValue: saved ?? "") ?? .dark
    }
    
    func applyTheme(_ theme: AppTheme) {
        currentTheme = theme
    }
}

// MARK: - View Extension for Theme Application
extension View {
    func themedBackground(_ theme: AppTheme) -> some View {
        self.background(theme.backgroundColor.ignoresSafeArea())
    }
    
    func themedForeground(_ theme: AppTheme) -> some View {
        self.foregroundColor(theme.primaryText)
    }
    
    /// Apply Night Mode red filter overlay
    func applyNightModeFilter(_ theme: AppTheme) -> some View {
        Group {
            if theme == .night {
                self
                    .colorMultiply(Color(red: 1.0, green: 0.4, blue: 0.3)) // Red filter
                    .background(theme.backgroundColor.ignoresSafeArea())
            } else {
                self
            }
        }
    }
}
