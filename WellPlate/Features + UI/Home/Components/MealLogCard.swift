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
                        .background(Capsule().fill(Color.orange))
                }

                Spacer()
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
                        .padding(.leading, 16)
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
        HStack {
            Text(entry.foodName)
                .font(.r(15, .regular))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(entry.calories) kcal")
                .font(.r(14, .regular))
                .foregroundColor(.secondary)
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
