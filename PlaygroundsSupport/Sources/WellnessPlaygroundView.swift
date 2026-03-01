import SwiftUI

struct WellnessPlaygroundView: View {
    @EnvironmentObject private var store: PlaygroundStore

    private var exerciseScore: Double {
        let stepsScore = min(store.todaySteps / 10_000, 1) * 12.5
        let energyScore = min(store.todayActiveEnergy / 500, 1) * 12.5
        return stepsScore + energyScore
    }

    private var sleepScore: Double {
        let hourScore = min(store.lastNightSleepHours / 8.0, 1) * 15
        let deepRatio = store.lastNightSleepHours > 0 ? (store.lastNightDeepSleepHours / store.lastNightSleepHours) : 0
        let deepScore = min(deepRatio / 0.22, 1) * 10
        return hourScore + deepScore
    }

    private var dietScore: Double {
        let proteinScore = min(store.totalProtein / 60, 1) * 13
        let fiberScore = min(store.totalFiber / 25, 1) * 12
        return proteinScore + fiberScore
    }

    private var screenTimeStressScore: Double {
        let hours = store.manualScreenTimeHours
        switch hours {
        case ...2:
            return 4
        case 2...4:
            return 8
        case 4...6:
            return 13
        case 6...8:
            return 18
        default:
            return 23
        }
    }

    private var exerciseStressContribution: Double { 25 - exerciseScore }
    private var sleepStressContribution: Double { 25 - sleepScore }
    private var dietStressContribution: Double { 25 - dietScore }

    private var totalStress: Double {
        exerciseStressContribution + sleepStressContribution + dietStressContribution + screenTimeStressScore
    }

    private var stressLabel: String {
        switch totalStress {
        case ..<25:
            return "Very Low"
        case ..<45:
            return "Balanced"
        case ..<65:
            return "Moderate"
        case ..<80:
            return "High"
        default:
            return "Very High"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    gaugeCard
                    factorsCard
                    controlsCard
                }
                .padding(16)
            }
            .background(Color.platformGroupedBackground)
            .navigationTitle("Wellness")
        }
    }

    private var gaugeCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 14)
                    .frame(width: 170, height: 170)

                Circle()
                    .trim(from: 0, to: min(totalStress / 100, 1))
                    .stroke(
                        AngularGradient(
                            colors: [.green, .yellow, .orange, .red],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 170, height: 170)
                    .animation(.easeInOut(duration: 0.25), value: totalStress)

                VStack(spacing: 4) {
                    Text("\(Int(totalStress))")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Stress Level: \(stressLabel)")
                .font(.headline)
            Text("Move the sliders below to see how lifestyle factors shift your score.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }

    private var factorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Factor Breakdown")
                .font(.headline)

            FactorRow(title: "Exercise", detail: "\(Int(store.todaySteps)) steps, \(Int(store.todayActiveEnergy)) kcal", value: exerciseStressContribution, color: .blue)
            Divider()
            FactorRow(title: "Sleep", detail: String(format: "%.1f h total, %.1f h deep", store.lastNightSleepHours, store.lastNightDeepSleepHours), value: sleepStressContribution, color: .indigo)
            Divider()
            FactorRow(title: "Diet", detail: "\(Int(store.totalProtein))g protein, \(Int(store.totalFiber))g fiber", value: dietStressContribution, color: .green)
            Divider()
            FactorRow(title: "Screen Time", detail: String(format: "%.1f h manual entry", store.manualScreenTimeHours), value: screenTimeStressScore, color: .orange)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Interactive Demo Controls")
                .font(.headline)

            SliderRow(
                title: "Steps",
                value: $store.todaySteps,
                range: 0...15_000,
                step: 500,
                formatter: { "\(Int($0))" }
            )
            SliderRow(
                title: "Active Energy",
                value: $store.todayActiveEnergy,
                range: 0...900,
                step: 25,
                formatter: { "\(Int($0)) kcal" }
            )
            SliderRow(
                title: "Sleep",
                value: $store.lastNightSleepHours,
                range: 3...10,
                step: 0.25,
                formatter: { String(format: "%.1f h", $0) }
            )
            SliderRow(
                title: "Deep Sleep",
                value: $store.lastNightDeepSleepHours,
                range: 0.4...3.0,
                step: 0.1,
                formatter: { String(format: "%.1f h", $0) }
            )
            SliderRow(
                title: "Screen Time",
                value: $store.manualScreenTimeHours,
                range: 0...12,
                step: 0.5,
                formatter: { String(format: "%.1f h", $0) }
            )
        }
        .padding(18)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.platformBackground)
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

private struct FactorRow: View {
    let title: String
    let detail: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.2))
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.7), lineWidth: 1)
                )
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1f", value))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(formatter(value))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(.orange)
        }
    }
}

#Preview {
    WellnessPlaygroundView()
        .environmentObject(PlaygroundStore())
}
