import SwiftUI

// MARK: - HydrationCard
// Shows a row of 8 water-glass icons; filled ones are tinted blue.
// The user increments with the + button or decrements by tapping a filled glass.

struct HydrationCard: View {

    @Binding var glassesConsumed: Int
    let totalGlasses: Int
    var cupSizeML: Int = 250

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hydration")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 2) {
                        Text("\(glassesConsumed)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hue: 0.58, saturation: 0.65, brightness: 0.75))
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: glassesConsumed)
                        
                        Text("of \(totalGlasses) cups")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text("· \(glassesConsumed * cupSizeML) mL")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hue: 0.58, saturation: 0.50, brightness: 0.70))
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: glassesConsumed)
                    }
                } // end VStack(alignment: .leading)
                
                Spacer()
                
                if glassesConsumed < totalGlasses {
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
            }
            // Glass icons
            HStack(spacing: 8) {
                ForEach(0..<totalGlasses, id: \.self) { index in
                    GlassIcon(isFilled: index < glassesConsumed)
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
        HapticService.impact(.light)
        SoundService.playConfirmation()
        glassesConsumed += 1
    }

    private func toggleGlass(at index: Int) {
        HapticService.impact(.light)
        SoundService.playConfirmation()
        if index < glassesConsumed {
            glassesConsumed = index
        } else {
            glassesConsumed = index + 1
        }
    }
}

// MARK: - GlassIcon

private struct GlassIcon: View {
    let isFilled: Bool

    private let filledColor = Color(hue: 0.58, saturation: 0.65, brightness: 0.82)
    private let emptyColor  = Color(hue: 0.58, saturation: 0.15, brightness: 0.88)

    var body: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 22))
            .foregroundStyle(isFilled ? filledColor : emptyColor)
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
