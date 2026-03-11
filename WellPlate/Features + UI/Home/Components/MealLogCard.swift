import SwiftUI

struct MealLogCard: View {
    let foodLogs: [FoodLogEntry]
    let isToday: Bool
    var onDelete: (FoodLogEntry) -> Void
    var onAddAgain: (FoodLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(isToday ? "Today's Meals" : "Meals")
                    .font(.r(.headline, .semibold))
                    .foregroundColor(.primary)

                if !foodLogs.isEmpty {
                    Text("\(foodLogs.count)")
                        .font(.r(12, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.brand))
                }

                Spacer()

                if !foodLogs.isEmpty {
                    Text("\(totalCalories) kcal total")
                        .font(.r(.caption, .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)

            if foodLogs.isEmpty {
                emptyState
            } else {
                mealList
            }
        }
    }

    // MARK: - Meal List Card

    private var mealList: some View {
        VStack(spacing: 0) {
            ForEach(Array(foodLogs.enumerated()), id: \.element.id) { index, entry in
                mealRow(entry: entry)
                    .contextMenu {
                        Button {
                            HapticService.impact(.light)
                            onAddAgain(entry)
                        } label: {
                            Label("Add Again", systemImage: "plus.circle.fill")
                        }
                        Divider()
                        Button(role: .destructive) {
                            onDelete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }

                if index < foodLogs.count - 1 {
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
        .padding(.horizontal, 16)
    }

    private func mealRow(entry: FoodLogEntry) -> some View {
        HStack(spacing: 12) {
            // Time + color accent
            VStack(spacing: 3) {
                Text(timeString(from: entry.createdAt))
                    .font(.r(10, .regular))
                    .foregroundColor(.secondary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(mealTimeColor(for: entry.createdAt))
                    .frame(width: 3, height: 28)
            }
            .frame(width: 32)

            // Food info
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.foodName)
                        .font(.r(15, .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(entry.calories)")
                            .font(.r(15, .semibold))
                            .foregroundColor(.primary)
                        Text("kcal")
                            .font(.r(11, .regular))
                            .foregroundColor(.secondary)
                    }
                }

                // Macro chips
                HStack(spacing: 5) {
                    // Quantity pill — show user-entered amount when available, else API serving
                    if let qty = entry.quantity, !qty.isEmpty, let unit = entry.quantityUnit {
                        macroPill("\(qty)\(unit)", color: AppColors.primary)
                    } else if let serving = entry.servingSize, !serving.isEmpty {
                        macroPill(serving, color: AppColors.primary)
                    }
                    macroPill("\(Int(entry.protein))g P", color: Color(red: 0.85, green: 0.25, blue: 0.25))
                    macroPill("\(Int(entry.carbs))g C", color: .blue)
                    macroPill("\(Int(entry.fat))g F", color: .orange)
                    if entry.fiber > 0.5 {
                        macroPill("\(Int(entry.fiber))g F·ib", color: .green)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Macro Pill

    private func macroPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.r(10, .medium))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    // MARK: - Helpers

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    private func mealTimeColor(for date: Date) -> Color {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11:  return .orange   // breakfast
        case 11..<15: return .blue     // lunch
        case 15..<19: return .purple   // afternoon
        default:      return .indigo   // evening / late night
        }
    }

    private var totalCalories: Int {
        foodLogs.reduce(0) { $0 + $1.calories }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.3))
            Text("No meals logged yet")
                .font(.r(.subheadline, .medium))
                .foregroundColor(.secondary)
            Text("Start typing above to log your first meal!")
                .font(.r(.caption, .regular))
                .foregroundColor(.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
        .padding(.horizontal, 16)
    }
}
