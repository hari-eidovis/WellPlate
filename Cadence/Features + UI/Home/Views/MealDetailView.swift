import SwiftUI

struct MealDetailView: View {
    let entry: FoodLogEntry
    var onDelete: () -> Void
    var onAddAgain: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed

    private var mealType: MealType? {
        guard let raw = entry.mealType else { return nil }
        return MealType(rawValue: raw)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: entry.createdAt)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: entry.createdAt)
    }

    private var servingLabel: String? {
        if let qty = entry.quantity, !qty.isEmpty, let unit = entry.quantityUnit {
            return "\(qty) \(unit)"
        }
        if let serving = entry.servingSize, !serving.isEmpty {
            return serving
        }
        return nil
    }

    private var sourceLabel: String {
        switch entry.logSource {
        case "barcode": return "Barcode Scan"
        case "voice":   return "Voice Input"
        case "text":    return "Text Input"
        default:        return "Manual"
        }
    }

    private var sourceIcon: String {
        switch entry.logSource {
        case "barcode": return "barcode.viewfinder"
        case "voice":   return "mic.fill"
        case "text":    return "keyboard"
        default:        return "square.and.pencil"
        }
    }

    private var confidenceLabel: String? {
        guard let c = entry.confidence else { return nil }
        if entry.logSource == "barcode" { return "Verified" }
        if c >= 0.8 { return "High Confidence" }
        if c >= 0.5 { return "Medium Confidence" }
        return "Estimated"
    }

    private var confidenceColor: Color {
        guard let c = entry.confidence else { return .secondary }
        if entry.logSource == "barcode" { return .green }
        if c >= 0.8 { return AppColors.primary }
        if c >= 0.5 { return .orange }
        return .red
    }

    // Max macro value for bar scaling
    private var maxMacro: Double {
        max(entry.protein, entry.carbs, entry.fat, entry.fiber, 1)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                nutritionCard
                if hasContext {
                    contextCard
                }
                provenanceCard
                actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Meal Details")
                    .font(.r(.headline, .semibold))
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 16) {
            // Meal type icon
            ZStack {
                Circle()
                    .fill(mealTimeColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: mealType?.icon ?? mealTimeIcon)
                    .font(.system(size: 26))
                    .foregroundColor(mealTimeColor)
            }

            // Food name
            Text(entry.foodName)
                .font(.r(.title2, .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Meal type + time
            HStack(spacing: 16) {
                if let meal = mealType {
                    Label(meal.displayName, systemImage: meal.icon)
                        .font(.r(.subheadline, .medium))
                        .foregroundColor(mealTimeColor)
                }

                Label(timeString, systemImage: "clock")
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(.secondary)
            }

            Text(dateString)
                .font(.r(.caption, .regular))
                .foregroundColor(.secondary)

            // Serving size pill
            if let serving = servingLabel {
                Text(serving)
                    .font(.r(.subheadline, .medium))
                    .foregroundColor(AppColors.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AppColors.primary.opacity(0.12))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    // MARK: - Nutrition Card

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nutrition")
                .font(.r(.headline, .semibold))
                .foregroundColor(.primary)

            // Calorie hero
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.calories)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.brand)
                    Text("calories")
                        .font(.r(.subheadline, .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Macro ring summary
                HStack(spacing: 20) {
                    macroCircle(value: entry.protein, label: "Protein", color: Color(red: 0.85, green: 0.25, blue: 0.25))
                    macroCircle(value: entry.carbs, label: "Carbs", color: .blue)
                    macroCircle(value: entry.fat, label: "Fat", color: .orange)
                }
            }

            Divider()

            // Detailed macro bars
            macroBar(label: "Protein", value: entry.protein, unit: "g", color: Color(red: 0.85, green: 0.25, blue: 0.25))
            macroBar(label: "Carbs", value: entry.carbs, unit: "g", color: .blue)
            macroBar(label: "Fat", value: entry.fat, unit: "g", color: .orange)
            macroBar(label: "Fiber", value: entry.fiber, unit: "g", color: .green)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func macroCircle(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(value))g")
                .font(.r(15, .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.r(10, .regular))
                .foregroundColor(.secondary)
        }
    }

    private func macroBar(label: String, value: Double, unit: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.r(.subheadline, .medium))
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.12))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(value / maxMacro)), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(String(format: "%.1f", value))\(unit)")
                .font(.r(.subheadline, .medium))
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .trailing)
        }
    }

    // MARK: - Context Card

    private var hasContext: Bool {
        entry.eatingTriggers?.isEmpty == false
            || entry.hungerLevel != nil
            || entry.presenceLevel != nil
            || (entry.reflection != nil && !entry.reflection!.isEmpty)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Eating Context")
                .font(.r(.headline, .semibold))
                .foregroundColor(.primary)

            // Triggers
            if let triggers = entry.eatingTriggers, !triggers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Triggers")
                        .font(.r(.caption, .semibold))
                        .foregroundColor(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(triggers, id: \.self) { trigger in
                            Text(trigger)
                                .font(.r(12, .medium))
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(AppColors.primary.opacity(0.12))
                                )
                        }
                    }
                }
            }

            // Hunger + Mindfulness
            if entry.hungerLevel != nil || entry.presenceLevel != nil {
                HStack(spacing: 16) {
                    if let hunger = entry.hungerLevel {
                        levelIndicator(label: "Hunger", value: hunger, icon: "flame.fill", color: .orange)
                    }
                    if let presence = entry.presenceLevel {
                        levelIndicator(label: "Mindfulness", value: presence, icon: "brain.head.profile.fill", color: .purple)
                    }
                }
            }

            // Reflection
            if let reflection = entry.reflection, !reflection.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reflection")
                        .font(.r(.caption, .semibold))
                        .foregroundColor(.secondary)
                    Text(reflection)
                        .font(.r(.subheadline, .regular))
                        .foregroundColor(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func levelIndicator(label: String, value: Double, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(label)
                    .font(.r(.caption, .semibold))
                    .foregroundColor(.secondary)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
                    .frame(height: 6)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(value)), height: 6)
                }
                .frame(height: 6)
            }

            Text("\(Int(value * 100))%")
                .font(.r(11, .medium))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Provenance Card

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.r(.headline, .semibold))
                .foregroundColor(.primary)

            detailRow(icon: sourceIcon, label: "Source", value: sourceLabel)

            if let conf = confidenceLabel {
                detailRow(icon: "checkmark.seal.fill", label: "Accuracy", value: conf, valueColor: confidenceColor)
            }

            if let barcode = entry.barcodeValue, !barcode.isEmpty {
                detailRow(icon: "barcode", label: "Barcode", value: barcode)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }

    private func detailRow(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.r(.subheadline, .medium))
                .foregroundColor(valueColor)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                HapticService.impact(.light)
                onAddAgain()
                dismiss()
            } label: {
                Label("Add Again", systemImage: "plus.circle.fill")
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(AppColors.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppColors.brand.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            Button {
                HapticService.impact(.medium)
                onDelete()
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var mealTimeColor: Color {
        let hour = Calendar.current.component(.hour, from: entry.createdAt)
        switch hour {
        case 5..<11:  return .orange
        case 11..<15: return .blue
        case 15..<19: return .purple
        default:      return .indigo
        }
    }

    private var mealTimeIcon: String {
        let hour = Calendar.current.component(.hour, from: entry.createdAt)
        switch hour {
        case 5..<11:  return "sunrise.fill"
        case 11..<15: return "sun.max.fill"
        case 15..<19: return "sunset.fill"
        default:      return "moon.stars.fill"
        }
    }
}

// MARK: - Flow Layout (for trigger tags)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
