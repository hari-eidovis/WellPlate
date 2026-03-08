import SwiftUI
import SwiftData

// MARK: - WellnessCalendarView

struct WellnessCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var userGoalsList: [UserGoals]
    @StateObject private var viewModel = WellnessCalendarViewModel()

    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols
    private var currentGoals: UserGoals { userGoalsList.first ?? UserGoals.defaults() }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                calendarSection
                detailSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle("Wellness Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Home")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundStyle(Color(hue: 0.40, saturation: 0.55, brightness: 0.72))
                }
            }
        }
        .onAppear {
            viewModel.bind(modelContext)
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(spacing: 14) {
            // Month navigation
            HStack {
                Button { viewModel.advanceMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }

                Spacer()

                Text(viewModel.monthYearString)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Button { viewModel.advanceMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
            }

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(height: 20)
                }
            }

            // Day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                // Empty cells for offset
                ForEach(0..<viewModel.firstWeekdayOffset, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }

                ForEach(viewModel.daysInMonth, id: \.self) { date in
                    CalendarDayCell(
                        date: date,
                        isToday: viewModel.isToday(date),
                        isSelected: viewModel.isSelected(date),
                        hasData: viewModel.hasData(for: date)
                    )
                    .onTapGesture {
                        HapticService.impact(.light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            viewModel.loadData(for: date)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
        .padding(.top, 8)
    }

    // MARK: - Detail Section

    private var detailSection: some View {
        VStack(spacing: 14) {
            // Date header
            HStack {
                Text(selectedDateString)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 4)

            moodCard(viewModel.dayLog)

            if let log = viewModel.dayLog {
                hydrationCard(log)
                activityCard(log)
                stressCard(log)
            } else {
                if viewModel.hasHealthKitActivityData {
                    activityCard(nil)
                }
                if !viewModel.hasHealthKitActivityData && viewModel.foodEntries.isEmpty {
                    emptyDayCard
                }
            }

            foodCard
        }
    }

    // MARK: - Mood Card

    private func moodCard(_ log: WellnessDayLog?) -> some View {
        detailCard(icon: "face.smiling", iconColor: moodColor(log), title: "Mood") {
            if let mood = log?.mood {
                HStack(spacing: 14) {
                    Text(mood.emoji)
                        .font(.system(size: 44))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mood.label)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(mood.accentColor)

                        Text("Mood check-in recorded")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "face.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No mood logged")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func moodColor(_ log: WellnessDayLog?) -> Color {
        log?.mood?.accentColor ?? Color(hue: 0.76, saturation: 0.45, brightness: 0.78)
    }

    // MARK: - Hydration Card

    private func hydrationCard(_ log: WellnessDayLog) -> some View {
        let hydrationGoal = max(currentGoals.waterDailyCups, 1)
        let waterColor = Color(hue: 0.58, saturation: 0.65, brightness: 0.82)
        return detailCard(icon: "drop.fill", iconColor: waterColor, title: "Hydration") {
            VStack(spacing: 12) {
                HStack {
                    Text("\(log.waterGlasses)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(waterColor)

                    Text("/ \(hydrationGoal) glasses")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Percentage
                    Text("\(Int(Double(log.waterGlasses) / Double(hydrationGoal) * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }

                // Mini drop icons
                HStack(spacing: 6) {
                    ForEach(0..<hydrationGoal, id: \.self) { index in
                        Image(systemName: "drop.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                index < log.waterGlasses
                                    ? waterColor
                                    : waterColor.opacity(0.18)
                            )
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Activity Card

    private func activityCard(_ log: WellnessDayLog?) -> some View {
        let exerciseColor = Color(hue: 0.40, saturation: 0.62, brightness: 0.70)
        let calorieColor = Color(hue: 0.07, saturation: 0.75, brightness: 0.90)
        let stepColor = Color(hue: 0.76, saturation: 0.50, brightness: 0.75)
        let activity = viewModel.resolvedActivity(for: log)
        let activityDay = log?.day ?? viewModel.selectedDate
        let weekday = Calendar.current.component(.weekday, from: activityDay)
        let exerciseGoal = max(currentGoals.workoutMinutes(for: weekday), 0)
        let calorieGoal = max(currentGoals.activeEnergyGoalKcal, 1)
        let stepsGoal = max(currentGoals.dailyStepsGoal, 1)
        let exerciseProgress: CGFloat = {
            guard exerciseGoal > 0 else { return activity.exerciseMinutes > 0 ? 1.0 : 0.0 }
            return min(CGFloat(activity.exerciseMinutes) / CGFloat(exerciseGoal), 1.0)
        }()

        return detailCard(icon: "figure.run", iconColor: exerciseColor, title: "Activity") {
            VStack(spacing: 14) {
                activityRow(
                    icon: "timer",
                    label: "Exercise",
                    value: "\(activity.exerciseMinutes) min",
                    progress: exerciseProgress,
                    color: exerciseColor
                )
                activityRow(
                    icon: "flame.fill",
                    label: "Calories Burned",
                    value: "\(activity.caloriesBurned) cal",
                    progress: min(CGFloat(activity.caloriesBurned) / CGFloat(calorieGoal), 1.0),
                    color: calorieColor
                )
                activityRow(
                    icon: "figure.walk",
                    label: "Steps",
                    value: NumberFormatter.localizedString(
                        from: NSNumber(value: activity.steps), number: .decimal
                    ),
                    progress: min(CGFloat(activity.steps) / CGFloat(stepsGoal), 1.0),
                    color: stepColor
                )
            }
        }
    }

    private func activityRow(
        icon: String, label: String, value: String, progress: CGFloat, color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(label)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.15))
                            .frame(height: 6)

                        Capsule()
                            .fill(color)
                            .frame(width: max(geo.size.width * progress, 6), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - Stress Card

    private func stressCard(_ log: WellnessDayLog) -> some View {
        let stressColor: Color = {
            switch log.stressLevel {
            case "Low": return Color(hue: 0.38, saturation: 0.55, brightness: 0.75)
            case "Medium": return Color(hue: 0.12, saturation: 0.65, brightness: 0.90)
            case "High": return Color(hue: 0.0, saturation: 0.65, brightness: 0.85)
            default: return .secondary
            }
        }()

        let stressEmoji: String = {
            switch log.stressLevel {
            case "Low": return "😌"
            case "Medium": return "😐"
            case "High": return "😰"
            default: return "—"
            }
        }()

        return detailCard(icon: "brain.head.profile", iconColor: stressColor, title: "Stress") {
            if let level = log.stressLevel {
                HStack(spacing: 14) {
                    Text(stressEmoji)
                        .font(.system(size: 36))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(level)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(stressColor)

                        Text(stressTip(for: level))
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No stress data")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stressTip(for level: String) -> String {
        switch level {
        case "Low": return "Great work! Keep your calm routine going 🧘"
        case "Medium": return "Consider a short breathing exercise to unwind"
        case "High": return "High stress detected — try a walk or meditation 💆"
        default: return ""
        }
    }

    // MARK: - Food Card

    private var foodCard: some View {
        detailCard(
            icon: "fork.knife",
            iconColor: Color(hue: 0.07, saturation: 0.72, brightness: 0.92),
            title: "Food Log"
        ) {
            if viewModel.foodEntries.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No meals logged")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    // Macro summary row
                    HStack(spacing: 0) {
                        macroChip(label: "Cal", value: "\(viewModel.totalCalories)", color: .orange)
                        macroChip(label: "Protein", value: String(format: "%.0fg", viewModel.totalProtein), color: .red)
                        macroChip(label: "Carbs", value: String(format: "%.0fg", viewModel.totalCarbs), color: .blue)
                        macroChip(label: "Fat", value: String(format: "%.0fg", viewModel.totalFat), color: .yellow)
                    }

                    Divider()

                    // Food entries list
                    ForEach(viewModel.foodEntries, id: \.id) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.foodName)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                if let serving = entry.servingSize {
                                    Text(serving)
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Text("\(entry.calories) cal")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func macroChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty Day

    private var emptyDayCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No wellness data for this day")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Log your mood, water, exercise, and meals to see insights here.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Reusable Detail Card

    private func detailCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(iconColor.opacity(0.14))
                    )

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
    }

    // MARK: - Helpers

    private var selectedDateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: viewModel.selectedDate)
    }
}

// MARK: - CalendarDayCell

private struct CalendarDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let hasData: Bool

    private let accentColor = Color(hue: 0.40, saturation: 0.55, brightness: 0.72)

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Selected background
                if isSelected {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 36, height: 36)
                        .transition(.scale.combined(with: .opacity))
                } else if isToday {
                    Circle()
                        .stroke(accentColor, lineWidth: 2)
                        .frame(width: 36, height: 36)
                }

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 15, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white : (isToday ? accentColor : .primary))
            }
            .frame(width: 40, height: 40)

            // Data indicator dot
            Circle()
                .fill(hasData ? accentColor : .clear)
                .frame(width: 5, height: 5)
        }
        .frame(height: 50)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview("Wellness Calendar") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: WellnessDayLog.self, FoodLogEntry.self, FoodCache.self, UserGoals.self,
        configurations: config
    )
    return NavigationStack {
        WellnessCalendarView()
    }
    .modelContainer(container)
}
