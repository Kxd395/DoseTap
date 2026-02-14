import SwiftUI

// Extracted from SettingsView.swift — QuickLog button customization

// MARK: - QuickLog Customization View
struct QuickLogCustomizationView: View {
    @ObservedObject var settings = UserSettingsManager.shared
    @State private var showAddSheet = false
    @Environment(\.editMode) private var editMode
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    private var availableToAdd: [QuickLogButtonConfig] {
        let currentIds = Set(settings.quickLogButtons.map { $0.id })
        return UserSettingsManager.allAvailableEvents.filter { !currentIds.contains($0.id) }
    }
    
    var body: some View {
        List {
            // Preview Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(settings.quickLogButtons) { button in
                            QuickLogPreviewButton(config: button)
                        }
                        
                        // Empty slots - tappable to show add sheet
                        ForEach(0..<(16 - settings.quickLogButtons.count), id: \.self) { _ in
                            Button(action: {
                                showAddSheet = true
                            }) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 50)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundColor(.blue)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("QuickLog Grid (4×4)")
            } footer: {
                Text("\(settings.quickLogButtons.count) of 16 slots used. Tap + to add events.")
            }
            
            // Current Buttons (Editable)
            Section {
                ForEach(settings.quickLogButtons) { button in
                    HStack(spacing: 12) {
                        Image(systemName: button.icon)
                            .font(.title3)
                            .foregroundColor(button.color)
                            .frame(width: 30)
                        
                        Text(button.name)
                        
                        Spacer()
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let button = settings.quickLogButtons[index]
                        settings.removeQuickLogButton(id: button.id)
                    }
                }
                .onMove { source, destination in
                    settings.moveQuickLogButton(from: source, to: destination)
                }
            } header: {
                HStack {
                    Text("Active Buttons")
                    Spacer()
                    EditButton()
                        .font(.caption)
                }
            } footer: {
                Text("Swipe to remove. Drag to reorder.")
            }
            
            // Add Buttons Section
            Section {
                ForEach(availableToAdd) { button in
                    Button {
                        settings.addQuickLogButton(button)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: button.icon)
                                .font(.title3)
                                .foregroundColor(button.color)
                                .frame(width: 30)
                            
                            Text(button.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .disabled(settings.quickLogButtons.count >= 16)
                }
            } header: {
                Text("Available Events")
            } footer: {
                if settings.quickLogButtons.count >= 16 {
                    Text("Maximum 16 buttons reached. Remove one to add another.")
                        .foregroundColor(.orange)
                }
            }
            
            // Reset Section
            Section {
                Button(role: .destructive) {
                    settings.resetQuickLogButtons()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Customize QuickLog")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddQuickLogEventSheet(
                availableEvents: availableToAdd,
                onAdd: { button in
                    settings.addQuickLogButton(button)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Add QuickLog Event Sheet
struct AddQuickLogEventSheet: View {
    let availableEvents: [QuickLogButtonConfig]
    let onAdd: (QuickLogButtonConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if availableEvents.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("All Events Added!")
                            .font(.headline)
                        Text("You've added all available event types to your QuickLog panel.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(availableEvents) { button in
                            Button {
                                onAdd(button)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: button.icon)
                                        .font(.title3)
                                        .foregroundColor(button.color)
                                        .frame(width: 30)
                                    
                                    Text(button.name)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - QuickLog Preview Button
struct QuickLogPreviewButton: View {
    let config: QuickLogButtonConfig
    
    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 10)
                .fill(config.color.opacity(0.15))
                .frame(height: 40)
                .overlay(
                    Image(systemName: config.icon)
                        .font(.system(size: 16))
                        .foregroundColor(config.color)
                )
            
            Text(config.name)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
