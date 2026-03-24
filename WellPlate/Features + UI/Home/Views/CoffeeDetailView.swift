import SwiftUI
import SwiftData

// MARK: - CoffeeDetailView
// Full-screen detail view for daily coffee tracking.
// Mirrors WaterDetailView structure exactly.
// Handles its own type picker (so the picker appears regardless of which
// entry point the user took — card body tap or card + button).

struct CoffeeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allWellnessDayLogs: [WellnessDayLog]
    @Query private var userGoalsList: [UserGoals]

    let totalCups: Int
    let coffeeType: CoffeeType?

    // MARK: - State

    /// Handoff variable for the sheet→alert race-safe pattern.
    /// Set by the picker closure, read by onChange(of: showTypePicker).
    @State private var pendingType: CoffeeType? = nil
    @State private var showTypePicker  = false
    @State private var showWaterAlert  = false

    // MARK: - Colours

    private let coffeeColor      = Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
    private let coffeeColorLight = Color(hue: 0.08, saturation: 0.25, brightness: 0.97)

    // MARK: - Derived

    private var todayLog: WellnessDayLog? {
        allWellnessDayLogs.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    private var cupsConsumed: Int { todayLog?.coffeeCups ?? 0 }
    private var resolvedType: CoffeeType? { todayLog?.resolvedCoffeeType ?? coffeeType }
    private var caffeineMgPerCup: Int { resolvedType?.caffeineMg ?? 80 }
    private var totalCaffeineMg: Int { cupsConsumed * caffeineMgPerCup }

    private var progress: CGFloat {
        totalCups > 0 ? min(1.0, CGFloat(cupsConsumed) / CGFloat(totalCups)) : 0
    }
    private var cupsRemaining: Int { max(0, totalCups - cupsConsumed) }
    private var percentComplete: Int { Int(round(progress * 100)) }

    private var waterGoal: Int { userGoalsList.first?.waterDailyCups ?? 8 }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                cupGrid
                statsRow
                tipCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Coffee")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { removeCup() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(cupsConsumed > 0 ? coffeeColor : .secondary)
                    }
                    .disabled(cupsConsumed <= 0)

                    Button { addCup() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(cupsConsumed < totalCups ? coffeeColor : .secondary)
                    }
                    .disabled(cupsConsumed >= totalCups)
                }
                .padding(.horizontal, 8)
            }
        }
        // Type picker sheet — shown on first cup when no type is set.
        .sheet(isPresented: $showTypePicker) {
            CoffeeTypePickerSheet { type in
                pendingType = type
                showTypePicker = false   // onChange fires after sheet animation completes
            }
        }
        // Race-safe: alert fires only after the sheet has fully dismissed.
        .onChange(of: showTypePicker) { _, isShowing in
            guard !isShowing else { return }
            if let type = pendingType {
                pendingType = nil
                saveType(type)
                showWaterAlert = true
            } else {
                // User swiped picker away without selecting — revert the cup increment.
                updateCups(max(0, cupsConsumed - 1))
            }
        }
        .alert("Stay Hydrated!", isPresented: $showWaterAlert) {
            Button("Log Water") { logOneWater() }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("Coffee can cause dehydration. Want to log a glass of water too?")
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(coffeeColor.opacity(0.15), lineWidth: 10)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(coffeeColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 140, height: 140)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75), value: cupsConsumed)

                VStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(coffeeColor)

                    Text("\(cupsConsumed)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: cupsConsumed)

                    Text("of \(totalCups) cups")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 2) {
                Text("\(totalCaffeineMg) mg caffeine")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(coffeeColor)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: totalCaffeineMg)

                if let typeName = resolvedType?.displayName {
                    Text(typeName)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
    }

    // MARK: - Cup Grid

    private var cupGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Cups")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 16
            ) {
                ForEach(0..<totalCups, id: \.self) { index in
                    let isFilled = index < cupsConsumed
                    Button {
                        toggleCup(at: index)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: isFilled ? "cup.and.saucer.fill" : "cup.and.saucer")
                                .font(.system(size: 30))
                                .foregroundStyle(isFilled ? coffeeColor : Color(hue: 0.08, saturation: 0.15, brightness: 0.88))
                                .animation(.easeInOut(duration: 0.18), value: isFilled)

                            Text("\(caffeineMgPerCup) mg")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isFilled ? coffeeColorLight : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(CupButtonStyle())
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statPill(title: "Progress",  value: "\(percentComplete)%",   icon: "chart.bar.fill")
            statPill(title: "Caffeine",  value: "\(totalCaffeineMg) mg", icon: "bolt.fill")
            statPill(title: "Remaining", value: "\(cupsRemaining) cups", icon: "hourglass")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
    }

    private func statPill(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(coffeeColor)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: value)

            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tip Card

    private var tipCard: some View {
        let tips: [(String, String)] = [
            ("Coffee after 2 PM can disrupt your sleep quality", "moon.fill"),
            ("Stay hydrated — drink a glass of water between cups", "drop.fill"),
            ("Most adults can safely enjoy up to 4 cups per day", "exclamationmark.circle.fill"),
            ("Black coffee has virtually zero calories", "number.circle.fill"),
            ("A single espresso shot contains about 63 mg of caffeine", "info.circle.fill"),
        ]
        let tip = tips[Calendar.current.component(.hour, from: Date()) % tips.count]

        return HStack(spacing: 14) {
            Image(systemName: tip.1)
                .font(.system(size: 22))
                .foregroundStyle(coffeeColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(coffeeColorLight))

            VStack(alignment: .leading, spacing: 3) {
                Text("Coffee Tip")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(tip.0)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
    }

    // MARK: - Actions

    private func addCup() {
        guard cupsConsumed < totalCups else { return }
        HapticService.impact(.light)
        SoundService.playConfirmation()
        let newCount = cupsConsumed + 1
        updateCups(newCount)

        if newCount == 1 && todayLog?.coffeeType == nil {
            // First cup, no type set — show picker; alert fires after picker closes.
            showTypePicker = true
        } else {
            showWaterAlert = true
        }
    }

    private func removeCup() {
        guard cupsConsumed > 0 else { return }
        HapticService.impact(.light)
        updateCups(cupsConsumed - 1)
    }

    private func toggleCup(at index: Int) {
        HapticService.impact(.light)
        SoundService.playConfirmation()
        let newCount = index < cupsConsumed ? index : index + 1
        let wasAdding = newCount > cupsConsumed
        updateCups(newCount)

        if wasAdding {
            if newCount == 1 && todayLog?.coffeeType == nil {
                showTypePicker = true
            } else {
                showWaterAlert = true
            }
        }
    }

    private func updateCups(_ count: Int) {
        let log = fetchOrCreateTodayLog()
        log.coffeeCups = max(0, count)
        try? modelContext.save()
    }

    private func saveType(_ type: CoffeeType) {
        let log = fetchOrCreateTodayLog()
        log.coffeeType = type.rawValue
        try? modelContext.save()
    }

    private func logOneWater() {
        let log = fetchOrCreateTodayLog()
        log.waterGlasses = min(log.waterGlasses + 1, waterGoal)
        try? modelContext.save()
    }

    private func fetchOrCreateTodayLog() -> WellnessDayLog {
        if let existing = todayLog { return existing }
        let newLog = WellnessDayLog(day: Date())
        modelContext.insert(newLog)
        return newLog
    }
}

// MARK: - CupButtonStyle

private struct CupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoffeeDetailView(totalCups: 4, coffeeType: .latte)
    }
}
