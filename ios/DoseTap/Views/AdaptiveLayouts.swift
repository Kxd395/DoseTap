import SwiftUI
import os.log

// MARK: - Environment Key: isInSplitView

/// Signals child views whether they are embedded in a NavigationSplitView detail column.
/// When `true`, child views should skip their own NavigationView/NavigationStack wrapper
/// since the split view provides the navigation context.
private struct IsInSplitViewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isInSplitView: Bool {
        get { self[IsInSplitViewKey.self] }
        set { self[IsInSplitViewKey.self] = newValue }
    }
}

// MARK: - Adaptive Sidebar

/// Sidebar list for iPad NavigationSplitView. Shows all tab sections with icons.
struct AdaptiveSidebarView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        List {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.label, systemImage: tab.icon)
                }
                .listRowBackground(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundColor(selectedTab == tab ? .accentColor : .primary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("DoseTap")
    }
}

// MARK: - AdaptiveHStack

/// A container that renders as `HStack` when the horizontal size class is `.regular`
/// (iPad / large landscape) and as `VStack` when compact (iPhone portrait).
///
/// Usage:
/// ```swift
/// AdaptiveHStack(spacing: 16) {
///     LeftColumn()
///     RightColumn()
/// }
/// ```
struct AdaptiveHStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let spacing: CGFloat
    let verticalAlignment: VerticalAlignment
    let horizontalAlignment: HorizontalAlignment
    @ViewBuilder let content: () -> Content

    init(
        spacing: CGFloat = 16,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.verticalAlignment = verticalAlignment
        self.horizontalAlignment = horizontalAlignment
        self.content = content
    }

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: verticalAlignment, spacing: spacing) {
                content()
            }
        } else {
            VStack(alignment: horizontalAlignment, spacing: spacing) {
                content()
            }
        }
    }
}

// MARK: - Adaptive Column Wrapper

/// Wraps content with a maximum width on iPad to prevent overly wide layouts.
/// On compact (iPhone), content fills the available width as usual.
struct AdaptiveMaxWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
        } else {
            content
        }
    }
}

extension View {
    /// Constrains the view to a maximum width on regular size class (iPad).
    /// On compact (iPhone) this has no effect.
    func adaptiveMaxWidth(_ maxWidth: CGFloat = 700) -> some View {
        modifier(AdaptiveMaxWidth(maxWidth: maxWidth))
    }
}

// MARK: - Wide Layout Detection Helper

/// Returns `true` when the horizontal size class is `.regular` (iPad or wide landscape).
/// Useful for views that need to branch layout without using `AdaptiveHStack`.
struct WideLayoutReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder let content: (_ isWide: Bool) -> Content

    var body: some View {
        content(sizeClass == .regular)
    }
}
