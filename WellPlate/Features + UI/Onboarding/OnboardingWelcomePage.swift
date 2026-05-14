import SwiftUI

/// Screen 1: Welcome hero with Lottie loader cat animation.
struct OnboardingWelcomePage: View {
    var onGetStarted: () -> Void

    @State private var animate = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero animation
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.08))
                    .frame(width: 260, height: 260)
                    .scaleEffect(animate ? 1.0 : 0.6)
                    .opacity(animate ? 1 : 0)

                LottieLoopView(name: "Loader cat")
                    .frame(width: 220, height: 220)
                    .scaleEffect(animate ? 1.0 : 0.5)
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
