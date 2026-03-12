import SwiftUI

/// Screen 4: Completion / summary with celebratory animation.
struct OnboardingCompletionPage: View {
    let name: String
    let weight: Double
    let height: Double
    let weightUnit: WeightUnit
    let heightUnit: HeightUnit
    var onLetsGo: () -> Void

    @State private var animate = false
    @State private var confettiVisible = false

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "there" : trimmed
    }

    private var weightText: String {
        switch weightUnit {
        case .kg:  return "\(Int(weight)) kg"
        case .lbs: return "\(Int(weight * 2.20462)) lbs"
        }
    }

    private var heightText: String {
        "\(Int(height)) cm"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Celebration illustration
            ZStack {
                // Confetti particles
                ForEach(0..<12, id: \.self) { i in
                    ConfettiParticle(index: i, isVisible: confettiVisible)
                }

                // Success badge
                ZStack {
                    Circle()
                        .fill(AppColors.brand.opacity(0.12))
                        .frame(width: 120, height: 120)

                    Circle()
                        .fill(AppColors.brand.opacity(0.2))
                        .frame(width: 90, height: 90)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColors.brand)
                        .symbolRenderingMode(.hierarchical)
                }
                .scaleEffect(animate ? 1 : 0.3)
                .opacity(animate ? 1 : 0)
            }
            .frame(height: 220)
            .padding(.bottom, 24)

            // Title
            VStack(spacing: 12) {
                Text("You're all set, \(displayName)!")
                    .font(.r(.title2, .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .opacity(animate ? 1 : 0)
                    .offset(y: animate ? 0 : 15)

                Text("Your personalized wellness dashboard\nis ready. Let's begin!")
                    .font(.r(.body, .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .opacity(animate ? 1 : 0)
                    .offset(y: animate ? 0 : 15)
            }
            .padding(.bottom, 28)

            // Summary card
            VStack(spacing: 0) {
                SummaryRow(icon: "person.fill", label: "Name", value: displayName)

                Divider().padding(.horizontal, 16)

                SummaryRow(icon: "scalemass.fill", label: "Weight", value: weightText)

                Divider().padding(.horizontal, 16)

                SummaryRow(icon: "ruler.fill", label: "Height", value: heightText)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, 24)
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 20)

            Spacer()
            Spacer()

            // CTA
            OnboardingCTAButton("Let's Go! 🌿") {
                onLetsGo()
            }
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 30)

            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.2)) {
                animate = true
            }
            withAnimation(.easeOut(duration: 1.0).delay(0.5)) {
                confettiVisible = true
            }
        }
    }
}

// MARK: - Summary Row

private struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.brand)
                .frame(width: 24)

            Text(label)
                .font(.r(.subheadline, .medium))
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text(value)
                .font(.r(.subheadline, .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Confetti Particle

private struct ConfettiParticle: View {
    let index: Int
    let isVisible: Bool

    private var rotation: Double { Double(index) * 30 }
    private var distance: CGFloat { CGFloat(80 + (index % 3) * 30) }

    private var color: Color {
        let colors: [Color] = [
            AppColors.brand,
            .yellow.opacity(0.7),
            .pink.opacity(0.5),
            AppColors.brand.opacity(0.6),
            .orange.opacity(0.5),
            .mint.opacity(0.6)
        ]
        return colors[index % colors.count]
    }

    private var shape: some View {
        Group {
            if index % 3 == 0 {
                Circle().frame(width: 8, height: 8)
            } else if index % 3 == 1 {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 6, height: 10)
                    .rotationEffect(.degrees(Double(index) * 15))
            } else {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10))
            }
        }
    }

    var body: some View {
        shape
            .foregroundStyle(color)
            .offset(
                x: isVisible ? cos(rotation * .pi / 180) * distance : 0,
                y: isVisible ? sin(rotation * .pi / 180) * distance : 0
            )
            .scaleEffect(isVisible ? 1 : 0)
            .opacity(isVisible ? 0.7 : 0)
    }
}
