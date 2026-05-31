import SwiftUI
import SwiftData

// MARK: - WellnessCalendarView

struct WellnessCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userGoalsList: [UserGoals]
    @Query private var allWellnessDayLogs: [WellnessDayLog]
    @Query private var allFoodEntries: [FoodLogEntry]
    @StateObject private var viewModel = WellnessCalendarViewModel()
    @State private var showCalendar = false

    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols
    private var currentGoals: UserGoals { userGoalsList.first ?? UserGoals.defaults() }

    // MARK: - Themed Accents
    private let moodAccent = Color(hue: 0.76, saturation: 0.50, brightness: 0.78)
    private let waterAccent = Color(hue: 0.58, saturation: 0.68, brightness: 0.85)
    private let exerciseAccent = Color(hue: 0.40, saturation: 0.62, brightness: 0.72)
    private let calorieAccent = Color(hue: 0.06, saturation: 0.78, brightness: 0.92)
    private let stepsAccent = Color(hue: 0.76, saturation: 0.55, brightness: 0.78)
    private let foodAccent = Color(hue: 0.07, saturation: 0.72, brightness: 0.92)

    // MARK: - Activity Ring Colors (Apple Fitness style)
    private let moveRing = Color(red: 0.96, green: 0.26, blue: 0.31)      // red — Move
    private let exerciseRing = Color(red: 0.30, green: 0.82, blue: 0.42)  // green — Exercise
    private let standRing = Color(red: 0.36, green: 0.78, blue: 0.97)     // sky blue — Stand/Steps

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroHeader
                weekStrip
                if showCalendar { calendarSection.transition(.opacity.combined(with: .move(edge: .top))) }
                detailSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 36)
        }
        .background(backgroundCanvas)
        .scrollIndicators(.hidden)
        .simultaneousGesture(swipeGesture)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.bind(modelContext) }
        .onChange(of: allWellnessDayLogs) { viewModel.loadData(for: viewModel.selectedDate) }
        .onChange(of: allFoodEntries) { viewModel.loadData(for: viewModel.selectedDate) }
    }

    // MARK: - Swipe Gesture (preserved)

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5,
                      abs(horizontal) > 60 else { return }
                let dayDelta = horizontal < 0 ? 1 : -1
                guard let newDate = Calendar.current.date(
                    byAdding: .day, value: dayDelta, to: viewModel.selectedDate
                ) else { return }
                HapticService.impact(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    viewModel.loadData(for: newDate)
                }
            }
    }

    // MARK: - Background

    private var backgroundCanvas: some View {
        ZStack(alignment: .top) {
            HomePalette.background.ignoresSafeArea()
            LinearGradient(
                colors: [AppColors.brand.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 380)
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 16) {
            Button {
                HapticService.impact(.light)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    showCalendar.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(relativeEyebrow.uppercased())
                            .font(.r(11, .bold))
                            .tracking(1.4)
                            .foregroundStyle(AppColors.brand)
                        Text(selectedDateString)
                            .font(.r(24, .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    ZStack {
                        Circle()
                            .fill(AppColors.brand.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppColors.brand)
                            .rotationEffect(.degrees(showCalendar ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            snapshotRow
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(AppColors.brand.opacity(0.08), lineWidth: 1)
                )
                .appShadow(radius: 18, y: 8)
        )
    }

    private var snapshotRow: some View {
        let activity = viewModel.resolvedActivity(for: viewModel.dayLog)
        let stressLevel = viewModel.stressScore.map { StressLevel(score: $0) }
        let cups = viewModel.dayLog?.waterGlasses ?? 0
        let goalCups = max(currentGoals.waterDailyCups, 1)
        let mood = viewModel.dayLog?.mood

        return HStack(spacing: 8) {
            snapshotTile(
                emoji: mood?.emoji,
                icon: mood == nil ? "face.smiling" : nil,
                value: mood?.label ?? "—",
                label: "Mood",
                accent: mood?.accentColor ?? .secondary,
                hasData: mood != nil
            )
            snapshotTile(
                icon: "drop.fill",
                value: "\(cups)/\(goalCups)",
                label: "Water",
                accent: waterAccent,
                hasData: cups > 0
            )
            snapshotTile(
                icon: "figure.walk",
                value: shortNumber(activity.steps),
                label: "Steps",
                accent: stepsAccent,
                hasData: activity.steps > 0
            )
            snapshotTile(
                icon: "brain.head.profile",
                value: viewModel.stressScore.map { "\(Int($0))" } ?? "—",
                label: stressLevel?.label ?? "Stress",
                accent: stressLevel?.color ?? .secondary,
                hasData: viewModel.stressScore != nil
            )
        }
    }

    private func snapshotTile(
        emoji: String? = nil,
        icon: String? = nil,
        value: String,
        label: String,
        accent: Color,
        hasData: Bool
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(accent.opacity(hasData ? 0.18 : 0.08))
                    .frame(width: 34, height: 34)
                if let emoji {
                    Text(emoji).font(.system(size: 18))
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(hasData ? accent : .secondary)
                }
            }
            Text(value)
                .font(.r(13, .bold))
                .foregroundStyle(hasData ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.r(10, .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.55))
        )
    }

    // MARK: - Week Strip

    private var weekStrip: some View {
        let cal = Calendar.current
        let days: [Date] = (-3...3).compactMap {
            cal.date(byAdding: .day, value: $0, to: viewModel.selectedDate)
        }
        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                weekDayPill(day)
            }
        }
    }

    private func weekDayPill(_ day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: viewModel.selectedDate)
        let isToday = cal.isDateInToday(day)
        let hasData = viewModel.hasData(for: day)
        let isFuture = day > Date()
        let dayNum = cal.component(.day, from: day)

        return Button {
            guard !isFuture else { return }
            HapticService.impact(.light)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                viewModel.loadData(for: day)
            }
        } label: {
            VStack(spacing: 6) {
                Text(weekdayLetter(day))
                    .font(.r(10, .bold))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                Text("\(dayNum)")
                    .font(.r(17, .bold))
                    .foregroundStyle(
                        isSelected ? .white :
                            (isToday ? AppColors.brand :
                                (isFuture ? Color.secondary.opacity(0.35) : .primary))
                    )
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.95) : (hasData ? AppColors.brand : .clear))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(pillBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .opacity(isFuture ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func pillBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppColors.brand, AppColors.brand.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .appShadow(radius: 12, y: 5)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.card)
                .appShadow(radius: 4, y: 2)
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(spacing: 14) {
            HStack {
                calendarNavButton(icon: "chevron.left") { viewModel.advanceMonth(by: -1) }
                Spacer()
                Text(viewModel.monthYearString)
                    .font(.r(17, .bold))
                    .foregroundStyle(.primary)
                Spacer()
                calendarNavButton(icon: "chevron.right") { viewModel.advanceMonth(by: 1) }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.r(11, .bold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .frame(height: 20)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
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
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.card)
                .appShadow(radius: 16, y: 6)
        )
    }

    private func calendarNavButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.brand)
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppColors.brand.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Section

    private var detailSection: some View {
        VStack(spacing: 14) {
            moodCard(viewModel.dayLog)

            if let log = viewModel.dayLog {
                hydrationCard(log)
                activityCard(log)
            } else {
                if viewModel.isLoadingActivity || viewModel.hasHealthKitActivityData {
                    activityCard(nil)
                }
                if !viewModel.isLoadingActivity
                    && !viewModel.hasHealthKitActivityData
                    && viewModel.foodEntries.isEmpty
                    && viewModel.stressScore == nil {
                    emptyDayCard
                }
            }

            stressCard
            foodCard
        }
    }

    // MARK: - Mood Card

    private func moodCard(_ log: WellnessDayLog?) -> some View {
        let mood = log?.mood
        let accent = mood?.accentColor ?? moodAccent

        return detailCard(icon: "face.smiling.fill", iconColor: accent, title: "Mood") {
            if let mood {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [accent.opacity(0.32), accent.opacity(0.05)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 38
                                )
                            )
                            .frame(width: 78, height: 78)
                        Text(mood.emoji).font(.system(size: 48))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mood.label)
                            .font(.r(22, .bold))
                            .foregroundStyle(accent)
                        Text("Mood check-in recorded")
                            .font(.r(13, .regular))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                emptyRow(icon: "face.dashed", message: "No mood logged")
            }
        }
    }

    // MARK: - Hydration Card

    private func hydrationCard(_ log: WellnessDayLog) -> some View {
        let goal = max(currentGoals.waterDailyCups, 1)
        let pct = min(Double(log.waterGlasses) / Double(goal), 1.0)
        return detailCard(icon: "drop.fill", iconColor: waterAccent, title: "Hydration") {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(log.waterGlasses)")
                        .font(.r(36, .heavy))
                        .foregroundStyle(waterAccent)
                        .monospacedDigit()
                    Text("/ \(goal)")
                        .font(.r(16, .semibold))
                        .foregroundStyle(.secondary)
                    Text("glasses")
                        .font(.r(13, .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.r(13, .bold))
                        .foregroundStyle(waterAccent)
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(waterAccent.opacity(0.14)))
                }

                HStack(spacing: 6) {
                    ForEach(0..<goal, id: \.self) { index in
                        Image(systemName: "drop.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                index < log.waterGlasses
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [waterAccent, waterAccent.opacity(0.75)],
                                        startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(waterAccent.opacity(0.18))
                            )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Activity Card

    private func activityCard(_ log: WellnessDayLog?) -> some View {
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
        let calorieProgress = min(CGFloat(activity.caloriesBurned) / CGFloat(calorieGoal), 1.0)
        let stepsProgress = min(CGFloat(activity.steps) / CGFloat(stepsGoal), 1.0)

        return detailCard(icon: "figure.run", iconColor: exerciseAccent, title: "Activity") {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .top, spacing: 18) {
                    activityStat(
                        label: "Move",
                        value: "\(activity.caloriesBurned)",
                        unit: "cal"
                    )
                    activityStat(
                        label: "Exercise",
                        value: "\(activity.exerciseMinutes)",
                        unit: "min"
                    )
                    activityStat(
                        label: "Steps",
                        value: shortNumber(activity.steps),
                        unit: ""
                    )
                }

                Spacer(minLength: 8)

                triRingView(
                    outer: calorieProgress, outerColor: moveRing,
                    middle: exerciseProgress, middleColor: exerciseRing,
                    inner: stepsProgress, innerColor: standRing
                )
                .frame(width: 64, height: 64)
            }
        }
    }

    private func activityStat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.r(12, .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.r(22, .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.r(12, .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func triRingView(
        outer: CGFloat, outerColor: Color,
        middle: CGFloat, middleColor: Color,
        inner: CGFloat, innerColor: Color
    ) -> some View {
        ZStack {
            ring(progress: outer, color: outerColor, lineWidth: 7, diameter: 64)
            ring(progress: middle, color: middleColor, lineWidth: 7, diameter: 46)
            ring(progress: inner, color: innerColor, lineWidth: 7, diameter: 28)
        }
    }

    private func ring(progress: CGFloat, color: Color, lineWidth: CGFloat, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: progress)
        }
    }

    // MARK: - Stress Card

    private var stressCard: some View {
        let score = viewModel.stressScore
        let level: StressLevel? = score.map { StressLevel(score: $0) }
        let stressColor = level?.color ?? .secondary

        return detailCard(icon: "brain.head.profile", iconColor: stressColor, title: "Stress") {
            if let score, let level {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(stressColor.opacity(0.18), lineWidth: 7)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: min(score / 100, 1.0))
                            .stroke(
                                LinearGradient(
                                    colors: [stressColor, stressColor.opacity(0.7)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)
                            )
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(score))")
                            .font(.r(22, .heavy))
                            .foregroundStyle(stressColor)
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(level.label)
                            .font(.r(22, .bold))
                            .foregroundStyle(stressColor)
                        Text(level.encouragementText)
                            .font(.r(13, .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                emptyRow(icon: "brain.head.profile", message: "No stress data")
            }
        }
    }

    // MARK: - Food Card

    private var foodCard: some View {
        detailCard(icon: "fork.knife", iconColor: foodAccent, title: "Food Log") {
            if viewModel.foodEntries.isEmpty {
                emptyRow(icon: "tray", message: "No meals logged")
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        macroChip(label: "Cal", value: "\(viewModel.totalCalories)", color: AppColors.brand)
                        macroChip(label: "Protein", value: String(format: "%.0fg", viewModel.totalProtein), color: Color(hue: 0.00, saturation: 0.65, brightness: 0.85))
                        macroChip(label: "Carbs", value: String(format: "%.0fg", viewModel.totalCarbs), color: Color(hue: 0.58, saturation: 0.68, brightness: 0.85))
                        macroChip(label: "Fat", value: String(format: "%.0fg", viewModel.totalFat), color: Color(hue: 0.12, saturation: 0.78, brightness: 0.95))
                    }

                    VStack(spacing: 8) {
                        ForEach(viewModel.foodEntries, id: \.id) { entry in
                            foodRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func foodRow(_ entry: FoodLogEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(foodAccent.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foodAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(.r(14, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let serving = entry.servingSize {
                    Text(serving)
                        .font(.r(11, .regular))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.calories)")
                    .font(.r(15, .bold))
                    .foregroundStyle(AppColors.brand)
                    .monospacedDigit()
                Text("cal")
                    .font(.r(11, .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill).opacity(0.55))
        )
    }

    private func macroChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.r(16, .bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.r(9, .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    // MARK: - Empty States

    private var emptyDayCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppColors.brand.opacity(0.85))
            }
            Text("Nothing recorded yet")
                .font(.r(16, .bold))
                .foregroundStyle(.primary)
            Text("Log your mood, water, exercise, and meals to see insights here.")
                .font(.r(13, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.card)
                .appShadow(radius: 12, y: 4)
        )
    }

    private func emptyRow(icon: String, message: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(message)
                .font(.r(14, .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Reusable Card

    private func detailCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [iconColor.opacity(0.22), iconColor.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.r(16, .bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.card)
                .appShadow(radius: 14, y: 5)
        )
    }

    // MARK: - Helpers

    private var selectedDateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: viewModel.selectedDate)
    }

    private var relativeEyebrow: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let selected = cal.startOfDay(for: viewModel.selectedDate)
        let comps = cal.dateComponents([.day], from: selected, to: today)
        let days = comps.day ?? 0
        switch days {
        case 0:  return "Today"
        case 1:  return "Yesterday"
        case -1: return "Tomorrow"
        case 2...6:
            let f = DateFormatter(); f.dateFormat = "EEEE"
            return f.string(from: viewModel.selectedDate)
        case _ where days > 6:
            return "\(days) Days Ago"
        default:
            let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
            return f.string(from: viewModel.selectedDate)
        }
    }

    private func weekdayLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func shortNumber(_ value: Int) -> String {
        if value >= 10_000 {
            let k = Double(value) / 1000.0
            return String(format: "%.1fk", k)
        }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

// MARK: - CalendarDayCell

private struct CalendarDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let hasData: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppColors.brand, AppColors.brand.opacity(0.82)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: AppColors.brand.opacity(0.35), radius: 8, x: 0, y: 3)
                        .transition(.scale.combined(with: .opacity))
                } else if isToday {
                    Circle()
                        .strokeBorder(AppColors.brand, lineWidth: 2)
                        .frame(width: 36, height: 36)
                }
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.r(15, isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : (isToday ? AppColors.brand : .primary))
            }
            .frame(width: 40, height: 40)

            Circle()
                .fill(hasData ? AppColors.brand : .clear)
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
