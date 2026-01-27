//
//  PainTrackingUI.swift
//  DoseTap
//
//  Shared pain tracking components for pre-sleep and wake surveys.
//  Uses 0-10 numeric scale with granular location + laterality tracking.
//

import SwiftUI

// MARK: - Pain Level Picker (0-10 Scale)

struct PainLevelPicker: View {
    @Binding var selectedLevel: Int?
    @State private var showFullScale = false
    let context: String  // "right now" or "currently"
    
    // Quick buttons: 0, 2, 5, 8, 10
    private let quickLevels = [0, 2, 5, 8, 10]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Pain level \(context)?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Quick 5-button picker
            HStack(spacing: 8) {
                ForEach(quickLevels, id: \.self) { level in
                    painButton(level: level, isQuick: true)
                }
            }
            
            // "Pick exact" expander
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showFullScale.toggle()
                }
            } label: {
                HStack {
                    Text(showFullScale ? "Hide exact picker" : "Pick exact number")
                        .font(.subheadline)
                    Image(systemName: showFullScale ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.secondary)
            }
            
            // Full 0-10 scale (expanded)
            if showFullScale {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0...5, id: \.self) { level in
                            painButton(level: level, isQuick: false)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(6...10, id: \.self) { level in
                            painButton(level: level, isQuick: false)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Selected level with anchor text
            if let level = selectedLevel {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colorForLevel(level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(level)/10 – \(anchorLabel(level))")
                            .font(.subheadline.bold())
                        Text(anchorDescription(level))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(colorForLevel(level).opacity(0.1))
                .cornerRadius(10)
            }
        }
    }
    
    private func painButton(level: Int, isQuick: Bool) -> some View {
        let isSelected = selectedLevel == level
        let size: CGFloat = isQuick ? 60 : 44
        
        return Button {
            withAnimation(.spring(response: 0.2)) {
                selectedLevel = level
            }
        } label: {
            Text("\(level)")
                .font(isQuick ? .title2.bold() : .body.bold())
                .frame(width: size, height: size)
                .background(isSelected ? colorForLevel(level) : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? colorForLevel(level) : Color.gray.opacity(0.3), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 0: return .green
        case 1...3: return .yellow
        case 4...6: return .orange
        case 7...8: return .red
        default: return .purple
        }
    }
    
    private func anchorLabel(_ level: Int) -> String {
        switch level {
        case 0: return "No pain"
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        default: return "Very severe"
        }
    }
    
    private func anchorDescription(_ level: Int) -> String {
        switch level {
        case 0: return ""
        case 1...3: return "Noticeable but easy to ignore, does not limit activity"
        case 4...6: return "Hard to ignore, interferes with comfort and focus"
        case 7...8: return "Limits activity, difficult to sleep or stay asleep"
        default: return "Unbearable, cannot function normally"
        }
    }
}

// MARK: - Pain Location Picker (Granular Regions + Laterality)

struct PainLocationPicker: View {
    @Binding var selectedLocations: [PainLocationDetail]
    @Binding var primaryLocation: PainLocationDetail?
    @State private var showingSideSelector: PainRegion?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Where does it hurt?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Tap an area to add it")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Grouped by category
            VStack(spacing: 20) {
                regionCategory(title: "Head & Neck", regions: [.head, .jaw, .face, .neck])
                regionCategory(title: "Shoulder & Arms", regions: [.shoulder, .upperArm, .elbow, .forearm, .wrist, .hand])
                regionCategory(title: "Torso & Back", regions: [.upperBack, .midBack, .lowBack, .chest, .abdomen])
                regionCategory(title: "Hips & Legs", regions: [.hip, .thigh, .knee, .shin, .ankle, .foot])
                regionCategory(title: "General", regions: [.jointsWidespread, .muscleWidespread, .other])
            }
            
            // Selected locations summary
            if !selectedLocations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected areas:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    ForEach(selectedLocations, id: \.self) { location in
                        HStack {
                            Text(location.compactText)
                                .font(.subheadline)
                            Spacer()
                            if location == primaryLocation {
                                Text("Main")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                            Button {
                                removeLocation(location)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                // Primary location selector (if multiple)
                if selectedLocations.count > 1 {
                    primaryLocationSelector
                }
            }
        }
        .sheet(item: $showingSideSelector) { region in
            SideSelectorSheet(
                region: region,
                onSelect: { side in
                    addLocation(region: region, side: side)
                }
            )
            .presentationDetents([.height(280)])
        }
    }
    
    private func regionCategory(title: String, regions: [PainRegion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(regions, id: \.self) { region in
                    regionChip(region)
                }
            }
        }
    }
    
    private func regionChip(_ region: PainRegion) -> some View {
        let isSelected = selectedLocations.contains { $0.region == region }
        
        return Button {
            if isSelected {
                // Remove all instances of this region
                selectedLocations.removeAll { $0.region == region }
                if primaryLocation?.region == region {
                    primaryLocation = nil
                }
            } else {
                // Show side selector if region supports laterality
                if region.supportsLaterality {
                    showingSideSelector = region
                } else {
                    addLocation(region: region, side: .center)
                }
            }
        } label: {
            Text(region.displayText)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.red.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(isSelected ? .red : .primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var primaryLocationSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which is the main pain area?")
                .font(.subheadline.bold())
            
            ForEach(selectedLocations, id: \.self) { location in
                Button {
                    withAnimation(.spring(response: 0.2)) {
                        primaryLocation = location
                    }
                } label: {
                    HStack {
                        Image(systemName: primaryLocation == location ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(primaryLocation == location ? .red : .gray)
                        Text(location.displayText)
                        Spacer()
                    }
                    .padding()
                    .background(primaryLocation == location ? Color.red.opacity(0.1) : Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func addLocation(region: PainRegion, side: PainSide) {
        let newLocation = PainLocationDetail(region: region, side: side)
        selectedLocations.append(newLocation)
        
        // Auto-set as primary if first location
        if selectedLocations.count == 1 {
            primaryLocation = newLocation
        }
    }
    
    private func removeLocation(_ location: PainLocationDetail) {
        selectedLocations.removeAll { $0 == location }
        if primaryLocation == location {
            primaryLocation = selectedLocations.first
        }
    }
}

// MARK: - Side Selector Sheet

struct SideSelectorSheet: View {
    let region: PainRegion
    let onSelect: (PainSide) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Which side?")
                .font(.title3.bold())
            
            Text(region.displayText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(PainSide.allCases, id: \.self) { side in
                    Button {
                        onSelect(side)
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Text(side.emoji)
                                .font(.largeTitle)
                            Text(side.displayText)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Radiation Picker (for back/neck/leg pain)

struct RadiationPicker: View {
    @Binding var radiation: PainRadiation?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Does the pain radiate?")
                .font(.headline)
            
            Text("Optional – for back, neck, or leg pain")
                .font(.caption)
                .foregroundColor(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(PainRadiation.allCases, id: \.self) { rad in
                    radiationChip(rad)
                }
            }
        }
    }
    
    private func radiationChip(_ rad: PainRadiation) -> some View {
        let isSelected = radiation == rad
        
        return Button {
            withAnimation(.spring(response: 0.2)) {
                radiation = isSelected ? nil : rad
            }
        } label: {
            Text(rad.displayText)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(isSelected ? .orange : .primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
