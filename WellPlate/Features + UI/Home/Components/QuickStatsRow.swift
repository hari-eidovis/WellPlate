import SwiftUI

// MARK: - QuickStatsRow
// Two LiquidGaugeTile views side by side: water (wave fill), coffee (gradient fill).

struct QuickStatsRow: View {
    @Binding var hydrationGlasses: Int
    let hydrationGoal: Int
    @Binding var coffeeCups: Int
    let coffeeGoal: Int
    let coffeeType: CoffeeType?
    let yesterdayWater: Int
    let yesterdayCoffee: Int
    let cupSizeML: Int
    var onWaterTap: () -> Void
    var onCoffeeTap: () -> Void
    var onCoffeeLog: () -> Void
    var showWater: Bool = true
    var showCoffee: Bool = true

    private var waterDeltaText: String? {
        let diff = hydrationGlasses - yesterdayWater
        guard diff != 0 else { return nil }
        return diff > 0 ? "Δ +\(diff)" : "Δ \(diff)"
    }

    private var coffeeDeltaText: String? {
        let diff = coffeeCups - yesterdayCoffee
        guard diff != 0 else { return nil }
        return diff > 0 ? "Δ +\(diff)" : "Δ \(diff)"
    }

    private var waterSubtitle: String {
        "\(hydrationGlasses * cupSizeML) mL"
    }

    private var coffeeSubtitle: String? {
        guard coffeeCups > 0 else { return nil }
        let mg = coffeeCups * (coffeeType?.caffeineMg ?? 80)
        return "\(mg)mg caffeine"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            if showWater {
            LiquidGaugeTile(
                style: .water,
                emoji: "💧",
                label: "Water",
                count: hydrationGlasses,
                goal: hydrationGoal,
                subtitle: waterSubtitle,
                deltaText: waterDeltaText,
                deltaPositive: hydrationGlasses >= yesterdayWater,
                showIncrementButton: hydrationGlasses < hydrationGoal,
                onTap: { onWaterTap() },
                onIncrement: {
                    SoundService.play("water_log_sound", ext: "mp3")
                    hydrationGlasses += 1
                }
            )
            }

            if showCoffee {
            LiquidGaugeTile(
                style: .coffee,
                emoji: "☕",
                label: "Coffee",
                count: coffeeCups,
                goal: coffeeGoal,
                subtitle: coffeeSubtitle,
                deltaText: coffeeDeltaText,
                deltaPositive: coffeeCups >= yesterdayCoffee,
                showIncrementButton: coffeeCups < coffeeGoal,
                onTap: { onCoffeeTap() },
                onIncrement: {
                    SoundService.playConfirmation()
                    onCoffeeLog()
                }
            )
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview {
    QuickStatsRow(
        hydrationGlasses: .constant(5),
        hydrationGoal: 8,
        coffeeCups: .constant(2),
        coffeeGoal: 4,
        coffeeType: .latte,
        yesterdayWater: 4,
        yesterdayCoffee: 3,
        cupSizeML: 250,
        onWaterTap: {}, onCoffeeTap: {}, onCoffeeLog: {}
    )
    .padding()
}
