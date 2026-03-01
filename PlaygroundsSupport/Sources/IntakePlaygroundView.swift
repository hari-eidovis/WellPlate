import SwiftUI

struct IntakePlaygroundView: View {
    @EnvironmentObject private var store: PlaygroundStore
    @FocusState private var isInputFocused: Bool

    private let quickFoods = [
        "Apple",
        "Banana",
        "Chicken Rice",
        "Dal",
        "Salad",
        "Greek Yogurt",
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    summaryCard
                    addFoodCard
                    quickAddCard
                    weeklyCard
                    logCard
                }
                .padding(16)
            }
            .background(Color.platformGroupedBackground)
            .navigationTitle("WellPlate")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset Demo") {
                        store.resetDemo()
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(store.totalCalories)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("kcal logged")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CircularProgress(
                    progress: store.calorieProgress,
                    color: .orange,
                    lineWidth: 10
                )
                .frame(width: 80, height: 80)
            }

            MacroRow(
                protein: store.totalProtein,
                carbs: store.totalCarbs,
                fat: store.totalFat,
                goals: store.goals
            )
        }
        .padding(18)
        .background(cardBackground)
    }

    private var addFoodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log Food")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("Describe your meal...", text: $store.draftFood)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        store.addDraftFood()
                    }

                Button("Add") {
                    store.addDraftFood()
                    isInputFocused = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Text("Runs entirely offline in this Playground build.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Add")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickFoods, id: \.self) { food in
                        Button(food) {
                            store.addFood(named: food)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var weeklyCard: some View {
        let weekly = store.weeklyCalories
        let maxCalories = max(1, weekly.map(\.calories).max() ?? 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("7-Day Calories")
                    .font(.headline)
                Spacer()
                Text("\(weekly.last?.calories ?? 0) today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(weekly) { day in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.orange.opacity(0.35), .orange],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: max(10, CGFloat(day.calories) / CGFloat(maxCalories) * 110))

                        Text(Self.dayFormatter.string(from: day.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today Log")
                .font(.headline)

            if store.entries.isEmpty {
                Text("No food logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.entries) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.subheadline.weight(.semibold))
                            Text(Self.timeFormatter.string(from: entry.loggedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.calories) kcal")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()

                        Button {
                            store.remove(entry)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    if entry.id != store.entries.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.platformBackground)
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private struct MacroRow: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let goals: MacroGoals

    var body: some View {
        HStack(spacing: 8) {
            MacroChip(
                title: "Protein",
                value: "\(Int(protein))g",
                progress: min(protein / goals.protein, 1),
                color: .green
            )
            MacroChip(
                title: "Carbs",
                value: "\(Int(carbs))g",
                progress: min(carbs / goals.carbs, 1),
                color: .blue
            )
            MacroChip(
                title: "Fat",
                value: "\(Int(fat))g",
                progress: min(fat / goals.fat, 1),
                color: .pink
            )
        }
    }
}

private struct MacroChip: View {
    let title: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

private struct CircularProgress: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)
            Text("\(Int(progress * 100))%")
                .font(.caption.weight(.semibold))
        }
    }
}

#Preview {
    IntakePlaygroundView()
        .environmentObject(PlaygroundStore())
}
