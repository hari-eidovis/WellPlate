import SwiftUI
import SwiftData

// MARK: - WaterDetailView
// Detail view for tracking daily water intake with interactive glass grid.

struct WaterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allWellnessDayLogs: [WellnessDayLog]

    let totalGlasses: Int
    let cupSizeML: Int

    private let waterColor = Color(hue: 0.58, saturation: 0.65, brightness: 0.82)
    private let waterColorLight = Color(hue: 0.58, saturation: 0.22, brightness: 0.96)

    private var todayLog: WellnessDayLog? {
        allWellnessDayLogs.first { Calendar.current.isDate($0.day, inSameDayAs: Date()) }
    }

    private var glassesConsumed: Int {
        todayLog?.waterGlasses ?? 0
    }

    private var progress: CGFloat {
        totalGlasses > 0 ? min(1.0, CGFloat(glassesConsumed) / CGFloat(totalGlasses)) : 0
    }

    private var totalML: Int { glassesConsumed * cupSizeML }
    private var goalML: Int { totalGlasses * cupSizeML }
    private var cupsRemaining: Int { max(0, totalGlasses - glassesConsumed) }
    private var percentComplete: Int { Int(round(progress * 100)) }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                glassGrid
                statsRow
                tipCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Hydration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { removeGlass() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(glassesConsumed > 0 ? waterColor : .secondary)
                    }
                    .disabled(glassesConsumed <= 0)

                    Button { addGlass() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(glassesConsumed < totalGlasses ? waterColor : .secondary)
                    }
                    .disabled(glassesConsumed >= totalGlasses)
                }
                .padding(.horizontal,8)
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 16) {
            ZStack {
                // Track
                Circle()
                    .stroke(waterColor.opacity(0.15), lineWidth: 10)
                    .frame(width: 140, height: 140)

                // Progress
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(waterColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 140, height: 140)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75), value: glassesConsumed)

                // Center content
                VStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(waterColor)

                    Text("\(glassesConsumed)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: glassesConsumed)

                    Text("of \(totalGlasses) cups")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(totalML) mL")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(waterColor)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: totalML)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
    }

    // MARK: - Glass Grid

    private var glassGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Glasses")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                ForEach(0..<totalGlasses, id: \.self) { index in
                    let isFilled = index < glassesConsumed
                    Button {
                        toggleGlass(at: index)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: isFilled ? "drop.fill" : "drop")
                                .font(.system(size: 30))
                                .foregroundStyle(isFilled ? waterColor : Color(hue: 0.58, saturation: 0.15, brightness: 0.88))
                                .animation(.easeInOut(duration: 0.18), value: isFilled)

                            Text("\(cupSizeML) mL")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isFilled ? waterColorLight : Color(.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(GlassButtonStyle())
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
            statPill(title: "Progress", value: "\(percentComplete)%", icon: "chart.bar.fill")
            statPill(title: "Consumed", value: "\(totalML) mL", icon: "drop.fill")
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
                .foregroundStyle(waterColor)

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
        let tips = [
            ("Drink a glass of water first thing in the morning", "sunrise.fill"),
            ("Keep a water bottle at your desk", "desktopcomputer"),
            ("Drink water before each meal", "fork.knife"),
            ("Set hourly reminders to stay hydrated", "bell.fill"),
            ("Eat water-rich fruits like watermelon", "leaf.fill"),
        ]
        let tip = tips[Calendar.current.component(.hour, from: Date()) % tips.count]

        return HStack(spacing: 14) {
            Image(systemName: tip.1)
                .font(.system(size: 22))
                .foregroundStyle(waterColor)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(waterColorLight)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Hydration Tip")
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

    private func addGlass() {
        guard glassesConsumed < totalGlasses else { return }
        HapticService.impact(.light)
        SoundService.playConfirmation()
        updateGlasses(glassesConsumed + 1)
    }

    private func removeGlass() {
        guard glassesConsumed > 0 else { return }
        HapticService.impact(.light)
        updateGlasses(glassesConsumed - 1)
    }

    private func toggleGlass(at index: Int) {
        HapticService.impact(.light)
        SoundService.playConfirmation()
        if index < glassesConsumed {
            updateGlasses(index)
        } else {
            updateGlasses(index + 1)
        }
    }

    private func updateGlasses(_ count: Int) {
        let log = fetchOrCreateTodayLog()
        log.waterGlasses = max(0, count)
        try? modelContext.save()
    }

    private func fetchOrCreateTodayLog() -> WellnessDayLog {
        if let existing = todayLog { return existing }
        let newLog = WellnessDayLog(day: Date())
        modelContext.insert(newLog)
        return newLog
    }
}

// MARK: - GlassButtonStyle

private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WaterDetailView(totalGlasses: 8, cupSizeML: 250)
    }
}
