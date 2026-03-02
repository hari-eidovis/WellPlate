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
                // Calorie progress
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(currentCalories)")
                            .font(.r(36, .bold))
                            .foregroundColor(.primary)
                        Text("/ \(dailyGoals.calories) kcal")
                            .font(.r(.subheadline, .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                    }

                    // Wide progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.12))

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange, Color.orange.opacity(0.75)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: min(geo.size.width * caloriesProgress, geo.size.width))
                        }
                    }
                    .frame(height: 10)
                }

                // 3 macro mini-rings
//                HStack(spacing: 0) {
//                    macroRing(
//                        value: currentCarbs,
//                        goal: dailyGoals.carbs,
//                        label: "Carbs",
//                        unit: "g",
//                        color: .blue
//                    )
//                    macroRing(
//                        value: currentProtein,
//                        goal: dailyGoals.protein,
//                        label: "Protein",
//                        unit: "g",
//                        color: .red
//                    )
//                    macroRing(
//                        value: currentFat,
//                        goal: dailyGoals.fat,
//                        label: "Fat",
//                        unit: "g",
//                        color: .yellow
//                    )
//                }
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

    // MARK: - Macro Ring

    private func macroRing(value: Int, goal: Int, label: String, unit: String, color: Color) -> some View {
        let progress = goal > 0 ? min(CGFloat(value) / CGFloat(goal), 1.0) : 0
        let ringColor = value <= goal ? color : .red

        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(value)")
                    .font(.r(14, .bold))
                    .foregroundColor(.primary)
            }
            .frame(width: 50, height: 50)

            Text(label)
                .font(.r(11, .medium))
                .foregroundColor(.primary)
            Text("\(value)/\(goal)\(unit)")
                .font(.r(9, .regular))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - All Macros Sheet

    private var allMacrosSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Calories bar (repeated at top of sheet)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
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
                                        colors: [Color.orange, Color.orange.opacity(0.8)],
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
}
