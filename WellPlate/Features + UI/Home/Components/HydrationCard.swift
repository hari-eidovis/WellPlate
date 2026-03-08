import SwiftUI

// MARK: - HydrationCard
// Shows a row of 8 water-glass icons; filled ones are tinted blue.
// The user increments with the + button or decrements by tapping a filled glass.

struct HydrationCard: View {

    @Binding var glassesConsumed: Int
    let totalGlasses: Int

    @State private var animatingIndex: Int? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hydration")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    // Shuttle animation: count slides up on increment, down on decrement.
                    HStack(spacing: 2) {
                        Text("\(glassesConsumed)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hue: 0.58, saturation: 0.65, brightness: 0.75))
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: glassesConsumed)

                        Text("of \(totalGlasses) glasses")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } // end VStack(alignment: .leading)

                Spacer()

                // + button
                Button {
                    addGlass()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hue: 0.58, saturation: 0.65, brightness: 0.82))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color(hue: 0.58, saturation: 0.22, brightness: 0.96))
                        )
                }
                .buttonStyle(.plain)
                .disabled(glassesConsumed >= totalGlasses)
            }

            // Glass icons
            HStack(spacing: 8) {
                ForEach(0..<totalGlasses, id: \.self) { index in
                    GlassIcon(
                        isFilled: index < glassesConsumed,
                        isAnimating: animatingIndex == index
                    )
                    .onTapGesture {
                        toggleGlass(at: index)
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
    }

    // MARK: - Actions

    private func addGlass() {
        guard glassesConsumed < totalGlasses else { return }
        let newIndex = glassesConsumed
        HapticService.impact(.light)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            glassesConsumed += 1
        }
        triggerBounce(at: newIndex)
    }

    private func toggleGlass(at index: Int) {
        HapticService.impact(.light)
        let newCount: Int
        if index < glassesConsumed {
            // Tap a filled glass → remove from this index onwards
            newCount = index
        } else {
            // Tap an empty glass → fill up to this index
            newCount = index + 1
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            glassesConsumed = newCount
        }
        triggerBounce(at: index)
    }

    private func triggerBounce(at index: Int) {
        animatingIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            animatingIndex = nil
        }
    }
}

// MARK: - GlassIcon

private struct GlassIcon: View {
    let isFilled: Bool
    let isAnimating: Bool

    private let filledColor = Color(hue: 0.58, saturation: 0.65, brightness: 0.82)
    private let emptyColor  = Color(hue: 0.58, saturation: 0.15, brightness: 0.88)

    var body: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 22))
            .foregroundStyle(isFilled ? filledColor : emptyColor)
            .scaleEffect(isAnimating ? 1.22 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.52), value: isAnimating)
            .animation(.easeInOut(duration: 0.18), value: isFilled)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    struct Wrap: View {
        @State var glasses = 5
        var body: some View {
            HydrationCard(glassesConsumed: $glasses, totalGlasses: 8)
                .padding()
        }
    }
    return Wrap()
}
