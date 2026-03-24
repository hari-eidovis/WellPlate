import SwiftUI

// MARK: - CoffeeCard
// Shows a row of cup icons tracking daily coffee consumption.
// Follows the exact same pattern as HydrationCard — direct binding mutations
// for all interactions so HomeView.onChange(of: coffeeCups) can persist everything.

struct CoffeeCard: View {

    @Binding var cupsConsumed: Int
    let totalCups: Int
    var coffeeType: CoffeeType? = nil
    var onTap: (() -> Void)? = nil

    private let coffeeColor      = Color(hue: 0.08, saturation: 0.70, brightness: 0.72)
    private let coffeeColorLight = Color(hue: 0.08, saturation: 0.25, brightness: 0.97)

    private var caffeineMg: Int {
        cupsConsumed * (coffeeType?.caffeineMg ?? 80)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coffee")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    HStack(spacing: 2) {
                        Text("\(cupsConsumed)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(coffeeColor.opacity(0.9))
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: cupsConsumed)

                        Text("of \(totalCups) cups")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)

                        if cupsConsumed > 0 {
                            Text("· \(caffeineMg) mg caffeine")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(coffeeColor.opacity(0.75))
                                .contentTransition(.numericText(countsDown: false))
                                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: caffeineMg)
                        }
                    }
                }

                Spacer()

                if cupsConsumed < totalCups {
                    Button {
                        addCup()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(coffeeColor)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(coffeeColorLight)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Cup icons
            HStack(spacing: 8) {
                ForEach(0..<totalCups, id: \.self) { index in
                    CoffeeIcon(isFilled: index < cupsConsumed, coffeeColor: coffeeColor)
                        .onTapGesture {
                            toggleCup(at: index)
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
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - Actions

    private func addCup() {
        guard cupsConsumed < totalCups else { return }
        HapticService.impact(.light)
        SoundService.playConfirmation()
        cupsConsumed += 1
    }

    private func toggleCup(at index: Int) {
        HapticService.impact(.light)
        SoundService.playConfirmation()
        if index < cupsConsumed {
            cupsConsumed = index
        } else {
            cupsConsumed = index + 1
        }
    }
}

// MARK: - CoffeeIcon

private struct CoffeeIcon: View {
    let isFilled: Bool
    let coffeeColor: Color

    private var emptyColor: Color {
        Color(hue: 0.08, saturation: 0.15, brightness: 0.88)
    }

    var body: some View {
        Image(systemName: isFilled ? "cup.and.saucer.fill" : "cup.and.saucer")
            .font(.system(size: 22))
            .foregroundStyle(isFilled ? coffeeColor : emptyColor)
            .animation(.easeInOut(duration: 0.18), value: isFilled)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    struct Wrap: View {
        @State var cups = 2
        var body: some View {
            CoffeeCard(cupsConsumed: $cups, totalCups: 4, coffeeType: .latte)
                .padding()
        }
    }
    return Wrap()
}
