import SwiftUI

struct CalorieHeroCard: View {
    let currentNutrition: NutritionalInfo?
    let dailyGoals: DailyGoals
    @State private var showAllMacros = false

    var body: some View {
        Button(action: {
            HapticService.impact(.light)
            showAllMacros = true
        }) {
            VStack(spacing: 16) {
                // Calorie header
//                HStack(alignment: .center) {
//                    VStack(alignment: .leading, spacing: 2) {
//                        HStack(alignment: .firstTextBaseline, spacing: 4) {
//                            Text("\(currentCalories)")
//                                .font(.r(38, .bold))
//                                .foregroundColor(.primary)
//                                .contentTransition(.numericText())
//                            Text("kcal")
//                                .font(.r(.subheadline, .medium))
//                                .foregroundColor(.secondary)
//                        }
//                        Text("of \(dailyGoals.calories) daily goal")
//                            .font(.r(.caption, .regular))
//                            .foregroundColor(.secondary)
//                    }
//
//                    Spacer()
//
//                    ZStack {
//                        Circle()
//                            .fill(Color.orange.opacity(0.12))
//                            .frame(width: 48, height: 48)
//                        Image(systemName: "flame.fill")
//                            .font(.system(size: 20))
//                            .foregroundColor(.orange)
//                    }
//                }
//
//                // Progress bar + remaining label
//                VStack(alignment: .trailing, spacing: 5) {
//                    GeometryReader { geo in
//                        ZStack(alignment: .leading) {
//                            RoundedRectangle(cornerRadius: 6)
//                                .fill(Color.gray.opacity(0.12))
//                            RoundedRectangle(cornerRadius: 6)
//                                .fill(
//                                    LinearGradient(
//                                        colors: isOverCalories
//                                            ? [Color.red, Color.orange.opacity(0.8)]
//                                            : [Color.orange, Color.orange.opacity(0.75)],
//                                        startPoint: .leading,
//                                        endPoint: .trailing
//                                    )
//                                )
//                                .frame(width: min(geo.size.width * caloriesProgress, geo.size.width))
//                        }
//                    }
//                    .frame(height: 10)
//
//                    Text(remainingText)
//                        .font(.r(.caption2, .medium))
//                        .foregroundColor(isOverCalories ? .red : .secondary)
//                }

                // Macro columns
                HStack(spacing: 0) {
                    macroColumn(
                        label: "Protein",
                        value: currentProtein,
                        goal: dailyGoals.protein,
                        unit: "g",
                        color: Color(red: 0.85, green: 0.25, blue: 0.25)
                    )

                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 1, height: 44)

                    macroColumn(
                        label: "Carbs",
                        value: currentCarbs,
                        goal: dailyGoals.carbs,
                        unit: "g",
                        color: .blue
                    )

                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 1, height: 44)

                    macroColumn(
                        label: "Fat",
                        value: currentFat,
                        goal: dailyGoals.fat,
                        unit: "g",
                        color: .orange
                    )
                }
                .padding(.top, 2)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .appShadow(radius: 15, y: 5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .sheet(isPresented: $showAllMacros) {
            allMacrosSheet
                .presentationDetents([.medium])
        }
    }

    // MARK: - Macro Column

    private func macroColumn(label: String, value: Int, goal: Int, unit: String, color: Color) -> some View {
        let progress = goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) : 0
        let isOver = value > goal

        return VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.r(17, .semibold))
                    .foregroundColor(isOver ? .red : .primary)
                Text(unit)
                    .font(.r(10, .regular))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isOver ? Color.red.opacity(0.7) : color)
                        .frame(width: min(geo.size.width * progress, geo.size.width))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 12)

            Text(label)
                .font(.r(11, .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - All Macros Sheet

    private var allMacrosSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Calories bar (repeated at top of sheet)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.brand)
                            Text("Calories")
                                .font(.r(13, .medium))
                        }
                        Spacer()
                        Text("\(currentCalories) / \(dailyGoals.calories)")
                            .font(.r(13, .medium))
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.1))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [AppColors.brand, AppColors.brand.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: min(geo.size.width * caloriesProgress, geo.size.width))
                        }
                    }
                    .frame(height: 8)
                }

                // Top row: Carbs, Protein, Fat
                HStack(spacing: 12) {
                    sheetMacroCircle(value: currentCarbs, goal: dailyGoals.carbs, label: "Carbs", unit: "g")
                    sheetMacroCircle(value: currentProtein, goal: dailyGoals.protein, label: "Protein", unit: "g")
                    sheetMacroCircle(value: currentFat, goal: dailyGoals.fat, label: "Fat", unit: "g")
                }

                // Bottom row: Sugar, Fiber, Sodium
                HStack(spacing: 12) {
                    sheetMacroCircle(value: currentSugar, goal: dailyGoals.sugar, label: "Sugar", unit: "g")
                    sheetMacroCircle(value: currentFiber, goal: dailyGoals.fiber, label: "Fiber", unit: "g")
                    sheetMacroCircle(value: currentSodium, goal: dailyGoals.sodium, label: "Sodium", unit: "mg")
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showAllMacros = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func sheetMacroCircle(value: Int, goal: Int, label: String, unit: String) -> some View {
        let isWithinLimit = value <= goal
        let circleColor: Color = isWithinLimit ? .green : .red

        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(CGFloat(value) / CGFloat(max(goal, 1)), 1.0))
                    .stroke(circleColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(.r(14, .bold))
                    .foregroundColor(.primary)
            }
            .frame(width: 55, height: 55)

            VStack(spacing: 1) {
                Text(label)
                    .font(.r(10, .medium))
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.r(9, .regular))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Computed Properties

    private var currentCalories: Int { currentNutrition?.calories ?? 0 }
    private var currentCarbs: Int { Int(currentNutrition?.carbs ?? 0) }
    private var currentProtein: Int { Int(currentNutrition?.protein ?? 0) }
    private var currentFat: Int { Int(currentNutrition?.fat ?? 0) }
    private var currentSugar: Int { Int((currentNutrition?.carbs ?? 0) * 0.4) }
    private var currentFiber: Int { Int(currentNutrition?.fiber ?? 0) }
    private var currentSodium: Int { Int(Double(currentCalories) * 1.2) }

    private var caloriesProgress: CGFloat {
        guard dailyGoals.calories > 0 else { return 0 }
        return CGFloat(currentCalories) / CGFloat(dailyGoals.calories)
    }

    private var isOverCalories: Bool { currentCalories > dailyGoals.calories }

    private var remainingText: String {
        let remaining = dailyGoals.calories - currentCalories
        if remaining > 0 {
            return "\(remaining) kcal remaining"
        } else if remaining == 0 {
            return "Goal reached!"
        } else {
            return "\(-remaining) kcal over goal"
        }
    }
}
