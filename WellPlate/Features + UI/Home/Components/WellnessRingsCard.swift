import SwiftUI

// MARK: - Ring Destination

enum WellnessRingDestination: Identifiable, Hashable {
    case calories, water, exercise, stress
    var id: Self { self }
}

// MARK: - WellnessRingsCard
// Shows four animated circular progress rings: Calories, Water, Exercise, Stress.

struct WellnessRingItem: Identifiable {
    let id = UUID()
    let label: String
    let sublabel: String
    let value: String
    let progress: CGFloat        // 0.0 – 1.0
    let color: Color
    let emojiOrSymbol: String?   // Optional emoji shown instead of value for Stress
    let inlineLabel: String?     // Optional text shown below emoji inside the ring
    let destination: WellnessRingDestination
    /// Plain-language explanation shown in the ring info sheet.
    var infoDescription: String? = nil
}

struct WellnessRingsCard: View {

    let rings: [WellnessRingItem]
    let completionPercent: Int
    var deltaValues: [WellnessRingDestination: Int]? = nil
    var onRingTap: (WellnessRingDestination) -> Void = { _ in }

    @State private var animate = false
    @State private var showRingInfo = false

    var body: some View {
        VStack(spacing: 32) {

            // Header row
            HStack {
                Spacer()

                Button {
                    HapticService.impact(.light)
                    showRingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What do these rings mean?")
            }

            // Rings row
            HStack(spacing: 0) {
                ForEach(rings) { ring in
                    WellnessRingButton(
                        ring: ring,
                        animate: animate,
                        deltaValue: deltaValues?[ring.destination]
                    ) {
                        HapticService.impact(.light)
                        onRingTap(ring.destination)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        )
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.15)) {
                animate = true
            }
        }
        .sheet(isPresented: $showRingInfo) {
            RingInfoSheet(rings: rings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - WellnessRingButton

private struct WellnessRingButton: View {

    let ring: WellnessRingItem
    let animate: Bool
    let deltaValue: Int?
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    // Track
                    Circle()
                        .stroke(ring.color.opacity(0.15), lineWidth: 7)
                        .frame(width: 64, height: 64)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: animate ? ring.progress : 0)
                        .stroke(
                            ring.color,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 64, height: 64)
                        .animation(
                            .spring(response: 1.1, dampingFraction: 0.72).delay(0.15),
                            value: animate
                        )

                    // Center: emoji (+ inline level label) or numeric value
                    if let emoji = ring.emojiOrSymbol {
                        VStack(spacing: 0) {
                            Text(emoji)
                                .font(.system(size: ring.inlineLabel != nil ? 18 : 22))
                            if let level = ring.inlineLabel {
                                Text(level)
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    } else {
                        Text(ring.value)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                }

                VStack(spacing: 2) {
                    Text(ring.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(ring.sublabel)
                        .font(.system(size: 8, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Group {
                    if let delta = deltaValue, delta != 0 {
                        let positive = delta > 0
                        let text = positive ? "Δ +\(delta)" : "Δ \(delta)"
                        Text(text)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(positive ? AppColors.success : AppColors.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((positive ? AppColors.success : AppColors.warning).opacity(0.12))
                            )
                    } else {
                        Color.clear.frame(height: 14)
                    }
                }
            }
        }
        .buttonStyle(RingButtonStyle(color: ring.color))
    }
}

// MARK: - RingButtonStyle

private struct RingButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - RingInfoSheet

private struct RingInfoSheet: View {
    let rings: [WellnessRingItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Each ring tracks one part of your day. Tap any ring on the home screen to dive in.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    ForEach(rings) { ring in
                        ringInfoRow(ring: ring)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Wellness Rings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func ringInfoRow(ring: WellnessRingItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(ring.color.opacity(0.18), lineWidth: 5)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: max(0.08, ring.progress))
                    .stroke(ring.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ring.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(ring.infoDescription ?? defaultDescription(for: ring.destination))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    /// Fallback copy when the caller didn't supply `infoDescription`.
    private func defaultDescription(for destination: WellnessRingDestination) -> String {
        switch destination {
        case .calories:
            return "Calories you've eaten today vs. your daily target."
        case .water:
            return "Glasses of water you've logged today vs. your hydration goal."
        case .exercise:
            return "Active calories you've burned today, pulled from Apple Health."
        case .stress:
            return "Today's stress level — computed from sleep, exercise, screen time, and vitals."
        }
    }
}

// MARK: - Preview

#Preview {
    WellnessRingsCard(
        rings: [
            WellnessRingItem(label: "Calories", sublabel: "/ 2000", value: "1420",
                             progress: 0.71, color: AppColors.brand, emojiOrSymbol: nil, inlineLabel: nil, destination: .calories),
            WellnessRingItem(label: "Water", sublabel: "/ 8 cups", value: "5",
                             progress: 0.625, color: .blue, emojiOrSymbol: nil, inlineLabel: nil, destination: .water),
            WellnessRingItem(label: "Exercise", sublabel: "/ 45 min", value: "32",
                             progress: 0.71, color: Color(hue: 0.45, saturation: 0.6, brightness: 0.72), emojiOrSymbol: nil, inlineLabel: nil, destination: .exercise),
            WellnessRingItem(label: "Stress", sublabel: "Low", value: "",
                             progress: 0.25, color: Color(hue: 0.76, saturation: 0.55, brightness: 0.78), emojiOrSymbol: "😌", inlineLabel: "Low", destination: .stress)
        ],
        completionPercent: 71
    )
    .padding()
}
