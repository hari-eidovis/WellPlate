import SwiftUI

/// Screen 1: Welcome hero with botanical illustration.
struct OnboardingWelcomePage: View {
    var onGetStarted: () -> Void

    @State private var animate = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero illustration
            ZStack {
                // Background circle
                Circle()
                    .fill(AppColors.brand.opacity(0.08))
                    .frame(width: 240, height: 240)
                    .scaleEffect(animate ? 1.0 : 0.6)

                // Inner ring
                Circle()
                    .stroke(AppColors.brand.opacity(0.15), lineWidth: 3)
                    .frame(width: 200, height: 200)
                    .scaleEffect(animate ? 1.0 : 0.5)

                // Floating wellness icons
                WellnessIconCluster(animate: animate)

                // Center plate icon
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppColors.brand)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(animate ? 1.0 : 0.3)
                    .opacity(animate ? 1 : 0)
            }
            .frame(height: 280)
            .padding(.bottom, 40)

            // Text
            VStack(spacing: 12) {
                Text("Welcome to")
                    .font(.r(.title2, .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .opacity(animate ? 1 : 0)
                    .offset(y: animate ? 0 : 20)

                HStack(spacing: 0) {
                    Text("Well")
                        .font(.r(36, .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Plate")
                        .font(.r(36, .bold))
                        .foregroundStyle(AppColors.brand)
                }
                .opacity(animate ? 1 : 0)
                .offset(y: animate ? 0 : 20)

                Text("Your personal wellness companion\nfor mindful eating, hydration,\nand balanced living.")
                    .font(.r(.body, .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 4)
                    .opacity(animate ? 1 : 0)
                    .offset(y: animate ? 0 : 20)
            }

            Spacer()
            Spacer()

            // CTA
            OnboardingCTAButton("Get Started") {
                onGetStarted()
            }
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 30)

            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                animate = true
            }
        }
    }
}

// MARK: - Floating Wellness Icons

private struct WellnessIconCluster: View {
    let animate: Bool

    private let icons: [(name: String, offset: CGSize, color: Color, delay: Double)] = [
        ("drop.fill",              CGSize(width: -80, height: -70),  .blue,   0.3),
        ("heart.fill",             CGSize(width:  90, height: -50),  .pink,   0.4),
        ("flame.fill",             CGSize(width: -95, height:  40),  .orange, 0.5),
        ("figure.walk",            CGSize(width:  85, height:  60),  .green,  0.6),
        ("fork.knife",             CGSize(width:  0,  height: -100), .brown,  0.35),
        ("moon.stars.fill",        CGSize(width: -50, height:  90),  .purple, 0.45),
    ]

    var body: some View {
        ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
            Image(systemName: icon.name)
                .font(.system(size: 20))
                .foregroundStyle(icon.color.opacity(0.6))
                .offset(icon.offset)
                .scaleEffect(animate ? 1 : 0)
                .opacity(animate ? 1 : 0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.65)
                    .delay(icon.delay),
                    value: animate
                )
        }
    }
}
