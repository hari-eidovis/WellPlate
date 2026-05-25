import SwiftUI
import Charts

struct NutritionSection: View {
    let data: ReportData

    private var goals: UserGoalsSnapshot { data.context.goals }
    private var narrative: SectionNarrative? { data.narratives.sectionNarratives["nutrition"] }

    var body: some View {
        ReportSectionCard(title: narrative?.headline ?? "Nutrition", domain: .nutrition) {
            if let n = narrative {
                Text(n.narrative)
                    .font(.r(.subheadline, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            calorieTrend
            macroBalance
            mealTimingHeatmap
            mealTypeDistribution
            eatingTriggers
            topFoodsList
            foodVariety
        }
    }

    // MARK: - Calorie Trend

    @ViewBuilder
    private var calorieTrend: some View {
        let calDays = data.context.days.compactMap { d -> (date: Date, cal: Int)? in
            guard let c = d.totalCalories else { return nil }
            return (date: d.date, cal: c)
        }
        if !calDays.isEmpty {
            Text("Daily Calories")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)
            Chart {
                ForEach(Array(calDays.enumerated()), id: \.offset) { _, day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("kcal", day.cal)
                    )
                    .foregroundStyle(barColor(day.cal))
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", goals.calorieGoal))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 130)

            let avg = calDays.map(\.cal).reduce(0, +) / calDays.count
            let over = calDays.filter { $0.cal > goals.calorieGoal }.count
            let under = calDays.filter { $0.cal < goals.calorieGoal }.count
            StatPillRow(pills: [
                (label: "Avg", value: "\(avg)", color: nil),
                (label: "Over", value: "\(over)d", color: .red),
                (label: "Under", value: "\(under)d", color: .green),
            ])
        }
    }

    private func barColor(_ cal: Int) -> Color {
        let ratio = Double(cal) / Double(goals.calorieGoal)
        if abs(ratio - 1.0) <= 0.1 { return .green }
        if abs(ratio - 1.0) <= 0.2 { return .orange }
        return .red
    }

    // MARK: - Macro Balance

    @ViewBuilder
    private var macroBalance: some View {
        let proteinDays = data.context.days.compactMap(\.totalProteinG)
        let carbDays = data.context.days.compactMap(\.totalCarbsG)
        let fatDays = data.context.days.compactMap(\.totalFatG)
        let fiberDays = data.context.days.compactMap(\.totalFiberG)

        if !proteinDays.isEmpty {
            Text("Macro Balance (avg vs goal)")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)

            let actual: [String: Double] = [
                "Protein": proteinDays.reduce(0, +) / Double(proteinDays.count),
                "Carbs": carbDays.reduce(0, +) / max(1, Double(carbDays.count)),
                "Fat": fatDays.reduce(0, +) / max(1, Double(fatDays.count)),
                "Fiber": fiberDays.reduce(0, +) / max(1, Double(fiberDays.count)),
            ]
            let goalMap: [String: Double] = [
                "Protein": Double(goals.proteinGoalGrams),
                "Carbs": Double(goals.carbsGoalGrams),
                "Fat": Double(goals.fatGoalGrams),
                "Fiber": Double(goals.fiberGoalGrams),
            ]
            MacroGroupedBarChart(actual: actual, goals: goalMap)
        }
    }

    // MARK: - Meal Timing Heatmap

    private var heatmapCells: [(dayLabel: String, bucket: String, count: Int)] {
        let buckets = ["6-10am", "10am-2pm", "2-6pm", "6-10pm", "10pm+"]
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        var cells: [(dayLabel: String, bucket: String, count: Int)] = []

        for day in data.context.days {
            let label = formatter.string(from: day.date)
            var bucketCounts = [String: Int]()
            for ts in day.mealTimestamps {
                let hour = Calendar.current.component(.hour, from: ts)
                let bucket: String
                switch hour {
                case 6..<10: bucket = buckets[0]
                case 10..<14: bucket = buckets[1]
                case 14..<18: bucket = buckets[2]
                case 18..<22: bucket = buckets[3]
                default: bucket = buckets[4]
                }
                bucketCounts[bucket, default: 0] += 1
            }
            for b in buckets {
                cells.append((dayLabel: label, bucket: b, count: bucketCounts[b, default: 0]))
            }
        }
        return cells
    }

    @ViewBuilder
    private var mealTimingHeatmap: some View {
        let cells = heatmapCells
        if cells.contains(where: { $0.count > 0 }) {
            Text("Meal Timing")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)
            MealTimingHeatmap(cells: cells)
        }
    }

    // MARK: - Meal Type Distribution

    private var aggregatedMealTypes: [String: Int] {
        var typeCounts: [String: Int] = [:]
        for day in data.context.days {
            for (type, count) in day.mealTypes {
                typeCounts[type, default: 0] += count
            }
        }
        let untagged = data.context.days.map(\.mealCount).reduce(0, +) - typeCounts.values.reduce(0, +)
        if untagged > 0 { typeCounts["untagged"] = untagged }
        return typeCounts
    }

    @ViewBuilder
    private var mealTypeDistribution: some View {
        let typeCounts = aggregatedMealTypes
        if !typeCounts.isEmpty {
            Text("Meal Types")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)

            let sorted = typeCounts.sorted { $0.value > $1.value }
            Chart {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Count", item.value),
                        y: .value("Type", item.key.capitalized)
                    )
                    .foregroundStyle(AppColors.brand.opacity(0.7))
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 10, design: .rounded)) }
            }
            .frame(height: CGFloat(typeCounts.count) * 28 + 10)
        }
    }

    // MARK: - Eating Triggers

    private var aggregatedTriggers: [String: Int] {
        var allTriggers: [String: Int] = [:]
        for day in data.context.days {
            for (trigger, count) in day.eatingTriggers {
                allTriggers[trigger, default: 0] += count
            }
        }
        return allTriggers
    }

    @ViewBuilder
    private var eatingTriggers: some View {
        let allTriggers = aggregatedTriggers
        if !allTriggers.isEmpty {
            Text("Eating Triggers")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)

            let sorted = allTriggers.sorted { $0.value > $1.value }
            Chart {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Count", item.value),
                        y: .value("Trigger", item.key.capitalized)
                    )
                    .foregroundStyle(WellnessDomain.mood.accentColor.opacity(0.7))
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(); AxisValueLabel().font(.system(size: 9, design: .rounded))
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 10, design: .rounded)) }
            }
            .frame(height: CGFloat(allTriggers.count) * 28 + 10)
        }
    }

    // MARK: - Top Foods

    @ViewBuilder
    private var topFoodsList: some View {
        let topFoods = data.context.topFoods
        if !topFoods.isEmpty {
            Text("Top Foods")
                .font(.r(.footnote, .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(topFoods.enumerated()), id: \.offset) { idx, food in
                HStack {
                    Text("\(idx + 1).")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(food.name)
                        .font(.r(.subheadline, .regular))
                    Spacer()
                    Text("\(food.count)x")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(food.totalCalories) kcal")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Food Variety

    @ViewBuilder
    private var foodVariety: some View {
        let uniqueFoods = Set(data.context.days.flatMap(\.foodNames)).count
        if uniqueFoods > 0 {
            HStack {
                Text("Food Variety:")
                    .font(.r(.footnote, .semibold))
                    .foregroundStyle(.secondary)
                Text("\(uniqueFoods) unique foods")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("(\(varietyBenchmark(uniqueFoods).label))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(varietyBenchmark(uniqueFoods).color)
            }
        }
    }

    private func varietyBenchmark(_ count: Int) -> (label: String, color: Color) {
        if count < 10 { return ("Limited variety", .red) }
        if count < 20 { return ("Moderate variety", .orange) }
        return ("Good variety", .green)
    }
}
