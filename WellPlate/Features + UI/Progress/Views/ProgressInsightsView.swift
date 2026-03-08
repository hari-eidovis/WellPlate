import SwiftUI
import Charts
import SwiftData

// MARK: - ProgressInsightsView

struct ProgressInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var allFoodLogs: [FoodLogEntry]
    @Query private var userGoalsList: [UserGoals]

    private var currentGoals: UserGoals {
        userGoalsList.first ?? UserGoals.defaults()
    }

    @State private var selectedTimeRange: TimeRange = .week
    @State private var selectedMetric: NutritionMetric = .calories
    @State private var showShareSheet = false
    @State private var selectedDay: Date?
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var scrollOffset: CGFloat = 0
    @State private var auroraPhase: CGFloat = 0
    @State private var safeTopInset: CGFloat = 0

    init() {
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let predicate = #Predicate<FoodLogEntry> { entry in
            entry.day >= ninetyDaysAgo
        }
        _allFoodLogs = Query(filter: predicate, sort: \.day, order: .forward)
    }

    // MARK: - Computed Properties

    private var dailyAggregates: [DailyAggregate] {
        let grouped = Dictionary(grouping: allFoodLogs) { $0.day }
        return grouped.map { day, logs in
            DailyAggregate(
                date: day,
                calories: logs.reduce(0) { $0 + $1.calories },
                protein: logs.reduce(0.0) { $0 + $1.protein },
                carbs: logs.reduce(0.0) { $0 + $1.carbs },
                fat: logs.reduce(0.0) { $0 + $1.fat },
                fiber: logs.reduce(0.0) { $0 + $1.fiber },
                mealCount: logs.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var filteredData: [DailyAggregate] {
        let cutoffDate = Calendar.current.date(byAdding: selectedTimeRange.calendarComponent,
                                               value: -selectedTimeRange.rawValue,
                                               to: Date()) ?? Date()
        return dailyAggregates.filter { $0.date >= cutoffDate }
    }

    private var currentPeriodStats: PeriodStats { calculateStats(for: filteredData) }

    private var previousPeriodStats: PeriodStats {
        let cutoffDate = Calendar.current.date(byAdding: selectedTimeRange.calendarComponent,
                                               value: -selectedTimeRange.rawValue * 2,
                                               to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: selectedTimeRange.calendarComponent,
                                            value: -selectedTimeRange.rawValue,
                                            to: Date()) ?? Date()
        return calculateStats(for: dailyAggregates.filter { $0.date >= cutoffDate && $0.date < endDate })
    }

    // MARK: - Colors

    private var bgGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(hex: "0F0F1A"), Color(hex: "1A1A2E")]
                : [Color(hex: "F5F5FF"), Color(hex: "EEF2FF")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C2E") : .white
    }

    private var cardShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.07)
    }

    // MARK: - Scroll progress

    private let heroHeight: CGFloat = 300
    private var heroVisible: Bool { scrollOffset > -heroHeight }

    /// 0 → hero fully visible, 1 → hero fully scrolled away.
    private var scrollProgress: CGFloat {
        let start: CGFloat = 80
        let end: CGFloat   = 260
        let offset = -scrollOffset
        return min(max((offset - start) / (end - start), 0), 1)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                bgGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            timeRangeSelector
                            mainChartCard
                            keyMetricsGrid
                            macroDistributionCard
                            trendsCard
                            detailedStatsCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .opacity(cardsAppeared ? 1 : 0)
                        .offset(y: cardsAppeared ? 0 : 30)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: cardsAppeared)
                    
                }
                .coordinateSpace(name: "scrollArea")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        scrollOffset = value
                    }
                }
            }
            .navigationTitle("Progress & Insights")
            .navigationBarTitleDisplayMode(.inline)
            .background(bgGradient.ignoresSafeArea())
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    headerAppeared = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    cardsAppeared = true
                }
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    auroraPhase = 1.0
                }
            }
            .toolbar{
                ToolbarItem(placement: .topBarLeading){
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
        
        // ─── Status-bar + nav-bar overlay ────────────────────────────────────
        // Sits OUTSIDE NavigationStack so it renders above the system white fill.
        .overlay(alignment: .top) {
            VStack(spacing: 0) {

                // ── Nav bar group: fades in as one unit ──────────────────────
                VStack(spacing: 0) {
                    // ① Status-bar fill
                    Color(hex: "FF6B35")
                        .frame(height: safeTopInset)
                        .allowsHitTesting(false)

                    // ② Nav bar row
                    HStack {
                        Text("Progress & Insights")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(
                                colorScheme == .dark
                                    ? Color(hex: "FFDAC8")
                                    : Color(hex: "C0421A")
                            )

                        Spacer()

                        HStack(spacing: 8) {
                            Button(action: { showShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color(hex: "FF6B35"))
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: "FF6B35").opacity(0.15))
                                    .clipShape(Circle())
                            }
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(hex: "FF6B35"))
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: "FF6B35").opacity(0.15))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        // Glass material + orange tint
                        ZStack {
                            Rectangle().fill(Material.regular)
                            Rectangle().fill(Color(hex: "FF6B35").opacity(0.7))
                        }
                    )
                }
                .opacity(scrollProgress)   // nav group fades in together

                // ── Sticky time range selector — independent opacity ──────────
                if scrollProgress > 0.75 {
                    timeRangeSelector
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .overlay(Divider(), alignment: .bottom)
                        .opacity(min(1, (scrollProgress - 0.75) / 0.25))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(edges: .top)
            .animation(.easeInOut(duration: 0.2), value: scrollProgress > 0.75)
        }
        // ─── Force light status-bar icons while hero is visible, ─────────────
        // dark (black) icons would clash with the white bg before scrolling.
        // When scrolled the orange bg needs white icons too.
        .preferredColorScheme(colorScheme)             // keep app scheme
        // Use UIKit bridge to lock status-bar style to .lightContent
        .background(StatusBarStyleModifier())
    }


    // MARK: - Time Range Selector

    private var timeRangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    HapticService.selectionChanged()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedTimeRange = range
                    }
                }) {
                    Text(range.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(selectedTimeRange == range ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            ZStack {
                                if selectedTimeRange == range {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(hex: "FF6B35"), Color(hex: "FF8C42")],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: Color(hex: "FF6B35").opacity(0.4), radius: 6, y: 3)
                                }
                            }
                        )
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: cardShadowColor, radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Main Chart Card

    private var mainChartCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedMetric.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(currentPeriodStats.average(for: selectedMetric), specifier: "%.0f")")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [selectedMetric.color, selectedMetric.color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(selectedMetric.unit)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: trendDirection.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text("\(abs(trendPercentage), specifier: "%.1f")%")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(trendDirection.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(trendDirection.color.opacity(0.13)))

                    Text("vs prev. period")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NutritionMetric.allCases, id: \.self) { metric in
                        Button(action: {
                            HapticService.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedMetric = metric
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text(metric.icon).font(.system(size: 11))
                                Text(metric.shortName).font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(selectedMetric == metric ? .white : .secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selectedMetric == metric ? metric.color : Color.secondary.opacity(0.1))
                            )
                            .shadow(color: selectedMetric == metric ? metric.color.opacity(0.35) : .clear,
                                    radius: 6, y: 3)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)

            if filteredData.isEmpty {
                emptyChartPlaceholder
            } else {
                chart.frame(height: 210)
            }
        }
        .padding(20)
        .glassCard(background: cardBackground, shadowColor: cardShadowColor)
    }

    private var chart: some View {
        Chart {
            ForEach(filteredData) { data in
                AreaMark(
                    x: .value("Date", data.date, unit: .day),
                    y: .value(selectedMetric.displayName, data.value(for: selectedMetric))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [selectedMetric.color.opacity(0.35), selectedMetric.color.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", data.date, unit: .day),
                    y: .value(selectedMetric.displayName, data.value(for: selectedMetric))
                )
                .foregroundStyle(selectedMetric.color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                if let sel = selectedDay, Calendar.current.isDate(data.date, inSameDayAs: sel) {
                    PointMark(x: .value("Date", data.date, unit: .day),
                              y: .value(selectedMetric.displayName, data.value(for: selectedMetric)))
                        .foregroundStyle(.white).symbolSize(80)
                    PointMark(x: .value("Date", data.date, unit: .day),
                              y: .value(selectedMetric.displayName, data.value(for: selectedMetric)))
                        .foregroundStyle(selectedMetric.color).symbolSize(40)
                }
            }

            if selectedMetric == .calories {
                RuleMark(y: .value("Goal", currentGoals.calorieGoal))
                    .foregroundStyle(Color.green.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: selectedTimeRange.xAxisStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: selectedTimeRange.dateFormat)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatAxisValue(v))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDay)
    }

    private func formatAxisValue(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.0fk", v / 1000) : String(format: "%.0f", v)
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.07)).frame(width: 80, height: 80)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            Text("No data yet")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
            Text("Start logging meals to see your progress")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(height: 210).frame(maxWidth: .infinity)
    }

    // MARK: - Key Metrics Grid

    private var keyMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            metricCard(title: "Total Intake",
                       value: "\(currentPeriodStats.totalCalories)", unit: "kcal",
                       icon: "flame.fill", color: Color(hex: "FF6B35"),
                       trend: calculateTrend(current: Double(currentPeriodStats.totalCalories),
                                             previous: Double(previousPeriodStats.totalCalories)))
            metricCard(title: "Avg Protein",
                       value: String(format: "%.0f", currentPeriodStats.avgProtein), unit: "g/day",
                       icon: "figure.strengthtraining.traditional", color: Color(hex: "FF4B6E"),
                       trend: calculateTrend(current: currentPeriodStats.avgProtein,
                                             previous: previousPeriodStats.avgProtein))
            metricCard(title: "Meals Logged",
                       value: "\(currentPeriodStats.totalMeals)", unit: "items",
                       icon: "fork.knife", color: Color(hex: "5E9FFF"),
                       trend: calculateTrend(current: Double(currentPeriodStats.totalMeals),
                                             previous: Double(previousPeriodStats.totalMeals)))
            metricCard(title: "Consistency",
                       value: "\(currentPeriodStats.consistencyScore)", unit: "%",
                       icon: "checkmark.seal.fill", color: Color(hex: "34C759"), trend: nil)
        }
    }

    private func metricCard(title: String, value: String, unit: String,
                             icon: String, color: Color, trend: Double?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.15)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(color)
                }
                Spacer()
                if let trend = trend {
                    HStack(spacing: 3) {
                        Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .black))
                        Text("\(abs(trend), specifier: "%.0f")%")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(trend >= 0 ? Color(hex: "34C759") : Color(hex: "FF4B6E"))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((trend >= 0 ? Color(hex: "34C759") : Color(hex: "FF4B6E")).opacity(0.12))
                    )
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    .textCase(.uppercase).tracking(0.5)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(background: cardBackground, shadowColor: cardShadowColor)
    }

    // MARK: - Macro Distribution Card

    private var macroDistributionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Macro Balance", subtitle: "avg per day")
            HStack(spacing: 24) {
                ZStack {
                    MacroDonutChart(protein: currentPeriodStats.avgProtein,
                                    carbs: currentPeriodStats.avgCarbs,
                                    fat: currentPeriodStats.avgFat)
                        .frame(width: 130, height: 130)
                    VStack(spacing: 2) {
                        let total = currentPeriodStats.avgProtein + currentPeriodStats.avgCarbs + currentPeriodStats.avgFat
                        Text(String(format: "%.0f", total))
                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.primary)
                        Text("g total").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    macroBar(color: Color(hex: "FF4B6E"), name: "Protein",
                             value: currentPeriodStats.avgProtein, pct: macroPercentage(.protein))
                    macroBar(color: Color(hex: "5E9FFF"), name: "Carbs",
                             value: currentPeriodStats.avgCarbs, pct: macroPercentage(.carbs))
                    macroBar(color: Color(hex: "FFD60A"), name: "Fat",
                             value: currentPeriodStats.avgFat, pct: macroPercentage(.fat))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .glassCard(background: cardBackground, shadowColor: cardShadowColor)
    }

    private func macroBar(color: Color, name: String, value: Double, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.primary)
                Spacer()
                Text(String(format: "%.0fg", value)).font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4).fill(color)
                        .frame(width: geo.size.width * (pct / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Trends Card

    private var trendsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Smart Insights", subtitle: "based on your data")
            VStack(spacing: 10) {
                if currentPeriodStats.avgCalories > Double(currentGoals.calorieGoal) {
                    insightRow(icon: "exclamationmark.triangle.fill",
                               gradientColors: [Color(hex: "FF6B35"), Color(hex: "FFA500")],
                               title: "Above Calorie Goal",
                               description: "\(Int(currentPeriodStats.avgCalories - Double(currentGoals.calorieGoal))) kcal over your daily target on average")
                } else {
                    insightRow(icon: "checkmark.circle.fill",
                               gradientColors: [Color(hex: "34C759"), Color(hex: "30D158")],
                               title: "Within Calorie Goal",
                               description: "You're nailing it! Staying on track consistently.")
                }
                if currentPeriodStats.avgProtein >= 100 {
                    insightRow(icon: "bolt.fill",
                               gradientColors: [Color(hex: "5E9FFF"), Color(hex: "007AFF")],
                               title: "Excellent Protein Intake",
                               description: "Averaging \(Int(currentPeriodStats.avgProtein))g/day — great for muscle support.")
                }
                if currentPeriodStats.consistencyScore >= 70 {
                    insightRow(icon: "star.fill",
                               gradientColors: [Color(hex: "FFD60A"), Color(hex: "FF9F0A")],
                               title: "Consistent Logger",
                               description: "You've tracked \(currentPeriodStats.consistencyScore)% of days — keep the streak alive!")
                }
                let streakDays = calculateCurrentStreak()
                if streakDays >= 3 {
                    insightRow(icon: "flame.fill",
                               gradientColors: [Color(hex: "FF4B6E"), Color(hex: "FF6B35")],
                               title: "\(streakDays)-Day Streak 🔥",
                               description: "Incredible consistency — don't break the chain!")
                }
            }
        }
        .padding(20)
        .glassCard(background: cardBackground, shadowColor: cardShadowColor)
    }

    private func insightRow(icon: String, gradientColors: [Color], title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            }
            .shadow(color: gradientColors.first?.opacity(0.4) ?? .clear, radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(description).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.08 : 0.04)))
    }

    // MARK: - Detailed Stats Card

    private var detailedStatsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Detailed Stats", subtitle: "period breakdown")
            VStack(spacing: 0) {
                ForEach(Array(statsRows.enumerated()), id: \.offset) { index, row in
                    statRow(data: row)
                    if index < statsRows.count - 1 {
                        Divider().padding(.leading, 50)
                    }
                }
            }
        }
        .padding(20)
        .glassCard(background: cardBackground, shadowColor: cardShadowColor)
    }

    private var statsRows: [(icon: String, color: Color, label: String, value: String)] {[
        ("arrow.up.circle.fill",   Color(hex: "FF6B35"), "Highest day",      "\(currentPeriodStats.maxCalories) kcal"),
        ("arrow.down.circle.fill", Color(hex: "5E9FFF"), "Lowest day",       "\(currentPeriodStats.minCalories) kcal"),
        ("leaf.fill",              Color(hex: "34C759"), "Avg fiber",        String(format: "%.1f g/day", currentPeriodStats.avgFiber)),
        ("star.fill",              Color(hex: "FFD60A"), "Most active day",  mostActiveDay)
    ]}

    private func statRow(data: (icon: String, color: Color, label: String, value: String)) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(data.color.opacity(0.13)).frame(width: 34, height: 34)
                Image(systemName: data.icon).font(.system(size: 15, weight: .semibold)).foregroundColor(data.color)
            }
            Text(data.label).font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
            Spacer()
            Text(data.value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.primary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var trendDirection: (icon: String, color: Color) {
        let change = currentPeriodStats.average(for: selectedMetric) -
                     previousPeriodStats.average(for: selectedMetric)
        if change > 0 { return ("arrow.up.right",   Color(hex: "34C759")) }
        else if change < 0 { return ("arrow.down.right", Color(hex: "FF4B6E")) }
        else { return ("minus", .gray) }
    }

    private var trendPercentage: Double {
        let current  = currentPeriodStats.average(for: selectedMetric)
        let previous = previousPeriodStats.average(for: selectedMetric)
        guard previous > 0 else { return 0 }
        return ((current - previous) / previous) * 100
    }

    private func calculateTrend(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    private func calculateStats(for data: [DailyAggregate]) -> PeriodStats {
        guard !data.isEmpty else {
            return PeriodStats(totalCalories: 0, avgCalories: 0, maxCalories: 0, minCalories: 0,
                               avgProtein: 0, avgCarbs: 0, avgFat: 0, avgFiber: 0,
                               totalMeals: 0, consistencyScore: 0)
        }
        let totalCalories = data.reduce(0) { $0 + $1.calories }
        let daysInPeriod  = selectedTimeRange.rawValue
        return PeriodStats(
            totalCalories:    totalCalories,
            avgCalories:      Double(totalCalories) / Double(data.count),
            maxCalories:      data.map { $0.calories }.max() ?? 0,
            minCalories:      data.map { $0.calories }.min() ?? 0,
            avgProtein:       data.reduce(0.0) { $0 + $1.protein } / Double(data.count),
            avgCarbs:         data.reduce(0.0) { $0 + $1.carbs }   / Double(data.count),
            avgFat:           data.reduce(0.0) { $0 + $1.fat }     / Double(data.count),
            avgFiber:         data.reduce(0.0) { $0 + $1.fiber }   / Double(data.count),
            totalMeals:       data.reduce(0) { $0 + $1.mealCount },
            consistencyScore: min(Int((Double(data.count) / Double(daysInPeriod)) * 100), 100)
        )
    }

    private func macroPercentage(_ macro: MacroType) -> Double {
        let total = currentPeriodStats.avgProtein + currentPeriodStats.avgCarbs + currentPeriodStats.avgFat
        guard total > 0 else { return 0 }
        switch macro {
        case .protein: return (currentPeriodStats.avgProtein / total) * 100
        case .carbs:   return (currentPeriodStats.avgCarbs   / total) * 100
        case .fat:     return (currentPeriodStats.avgFat     / total) * 100
        }
    }

    private var mostActiveDay: String {
        guard let maxDay = filteredData.max(by: { $0.mealCount < $1.mealCount }) else { return "N/A" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: maxDay.date)
    }

    private func calculateCurrentStreak() -> Int {
        guard !dailyAggregates.isEmpty else { return 0 }
        var streak = 0
        var current = Calendar.current.startOfDay(for: Date())
        for day in dailyAggregates.sorted(by: { $0.date > $1.date }) {
            guard Calendar.current.isDate(day.date, inSameDayAs: current) else { break }
            streak += 1
            current = Calendar.current.date(byAdding: .day, value: -1, to: current) ?? current
        }
        return streak
    }
}

// MARK: - UIKit bridge: force light-content (white) status-bar icons at all times
// This ensures the clock/battery text is white on the orange hero gradient
// AND white on the orange scrolled nav bar.

private struct StatusBarStyleModifier: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> StatusBarViewController { StatusBarViewController() }
    func updateUIViewController(_ vc: StatusBarViewController, context: Context) {}
}

private class StatusBarViewController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

// MARK: - Scroll Offset PreferenceKey

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Reusable Sub-views

private struct SectionHeader: View {
    let title: String; let subtitle: String
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.primary)
            Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
        }
    }
}

private struct HeroBadge: View {
    let value: String; let label: String
    var body: some View {
        HStack(spacing: 5) {
            Text(value).font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
        )
    }
}

// MARK: - Macro Donut Chart

struct MacroDonutChart: View {
    let protein: Double; let carbs: Double; let fat: Double

    private var total: Double { protein + carbs + fat }
    private var pP: Double { total > 0 ? protein / total : 0 }
    private var pC: Double { total > 0 ? carbs   / total : 0 }
    private var pF: Double { total > 0 ? fat     / total : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.1), lineWidth: 18)
            Circle().trim(from: 0, to: pP)
                .stroke(Color(hex: "FF4B6E"), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: 0, to: pC)
                .stroke(Color(hex: "5E9FFF"), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90 + pP * 360))
            Circle().trim(from: 0, to: pF)
                .stroke(Color(hex: "FFD60A"), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90 + (pP + pC) * 360))
        }
    }
}

// MARK: - Glass Card modifier

private struct GlassCardModifier: ViewModifier {
    let background: Color
    let shadowColor: Color
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(background)
                    .overlay {
                        if colorScheme == .dark {
                            RoundedRectangle(cornerRadius: 22)
                                .fill(.ultraThinMaterial)
                                .opacity(0.35)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(colorScheme == .dark ? 0.18 : 0.6),
                                        .white.opacity(0.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                ),
                                lineWidth: 0.75
                            )
                    }
                    .shadow(color: shadowColor, radius: 18, x: 0, y: 6)
            )
    }
}

extension View {
    func glassCard(background: Color, shadowColor: Color) -> some View {
        modifier(GlassCardModifier(background: background, shadowColor: shadowColor))
    }
}

// MARK: - NutritionMetric unit extension

extension NutritionMetric {
    var unit: String {
        switch self {
        case .calories:                     return "kcal avg/day"
        case .protein, .carbs, .fat, .fiber: return "g avg/day"
        }
    }
}

// ── Supporting enums & structs (unchanged) ──────────────────────────────────

enum TimeRange: Int, CaseIterable {
    case week = 7, twoWeeks = 14, month = 30
    var displayName: String {
        switch self { case .week: "7 Days"; case .twoWeeks: "14 Days"; case .month: "30 Days" }
    }
    var calendarComponent: Calendar.Component { .day }
    var xAxisStride: Calendar.Component {
        switch self { case .week, .twoWeeks: .day; case .month: .weekOfYear }
    }
    var dateFormat: Date.FormatStyle { .dateTime.month(.abbreviated).day() }
}

enum NutritionMetric: CaseIterable {
    case calories, protein, carbs, fat, fiber
    var displayName: String {
        switch self { case .calories: "Calories"; case .protein: "Protein";
                      case .carbs: "Carbs"; case .fat: "Fat"; case .fiber: "Fiber" }
    }
    var shortName: String {
        switch self { case .calories: "Cal"; case .protein: "Protein";
                      case .carbs: "Carbs"; case .fat: "Fat"; case .fiber: "Fiber" }
    }
    var icon: String {
        switch self { case .calories: "🔥"; case .protein: "🥩"; case .carbs: "🍞";
                      case .fat: "🥑"; case .fiber: "🌾" }
    }
    var color: Color {
        switch self {
        case .calories: Color(hex: "FF6B35"); case .protein: Color(hex: "FF4B6E")
        case .carbs:    Color(hex: "5E9FFF"); case .fat:     Color(hex: "FFD60A")
        case .fiber:    Color(hex: "34C759")
        }
    }
}

enum MacroType { case protein, carbs, fat }

struct DailyAggregate: Identifiable {
    let id = UUID()
    let date: Date; let calories: Int
    let protein, carbs, fat, fiber: Double
    let mealCount: Int
    func value(for metric: NutritionMetric) -> Double {
        switch metric {
        case .calories: Double(calories); case .protein: protein
        case .carbs: carbs; case .fat: fat; case .fiber: fiber
        }
    }
}

struct PeriodStats {
    let totalCalories: Int; let avgCalories: Double
    let maxCalories, minCalories: Int
    let avgProtein, avgCarbs, avgFat, avgFiber: Double
    let totalMeals: Int; let consistencyScore: Int
    func average(for metric: NutritionMetric) -> Double {
        switch metric {
        case .calories: avgCalories; case .protein: avgProtein
        case .carbs: avgCarbs; case .fat: avgFat; case .fiber: avgFiber
        }
    }
}

#Preview {
    ProgressInsightsView()
        .modelContainer(for: [FoodLogEntry.self], inMemory: true)
}
