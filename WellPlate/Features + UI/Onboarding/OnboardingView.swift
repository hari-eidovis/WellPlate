import SwiftUI

/// Root container for the 4-step onboarding flow.
/// Uses a `TabView` with page style for swiping between screens.
struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var userName = ""
    @State private var weightValue: Double = 70
    @State private var heightValue: Double = 170
    @State private var weightUnit: WeightUnit = .kg
    @State private var heightUnit: HeightUnit = .cm

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Background
            OnboardingBackground()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    // Back button
                    if currentPage > 0 {
                        Button {
                            HapticService.impact(.light)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                currentPage -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Spacer()

                    // Skip
                    if currentPage < 3 {
                        Button("Skip") {
                            HapticService.impact(.light)
                            completeOnboarding()
                        }
                        .font(.r(.subheadline, .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .frame(height: 44)

                // Pages
                TabView(selection: $currentPage) {
                    OnboardingWelcomePage {
                        advanceToPage(1)
                    }
                    .tag(0)

                    OnboardingNamePage(name: $userName) {
                        advanceToPage(2)
                    }
                    .tag(1)

                    OnboardingBodyPage(
                        weightValue: $weightValue,
                        heightValue: $heightValue,
                        weightUnit: $weightUnit,
                        heightUnit: $heightUnit
                    ) {
                        advanceToPage(3)
                    }
                    .tag(2)

                    OnboardingCompletionPage(
                        name: userName,
                        weight: weightValue,
                        height: heightValue,
                        weightUnit: weightUnit,
                        heightUnit: heightUnit
                    ) {
                        completeOnboarding()
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentPage)

                // Page indicator
                PageIndicator(currentPage: currentPage, totalPages: 4)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Actions

    private func advanceToPage(_ page: Int) {
        HapticService.impact(.light)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentPage = page
        }
    }

    private func completeOnboarding() {
        let manager = UserProfileManager.shared
        manager.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        manager.setWeight(weightValue, unit: weightUnit)
        manager.setHeight(heightValue, unit: heightUnit)
        manager.hasCompletedOnboarding = true
        HapticService.impact(.medium)
        onComplete()
    }
}

// MARK: - Background

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            // Subtle warm gradient
            LinearGradient(
                colors: [
                    AppColors.brand.opacity(0.04),
                    Color.clear,
                    AppColors.brand.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Page Indicator

struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? AppColors.brand : AppColors.brand.opacity(0.2))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
            }
        }
    }
}

// MARK: - Onboarding CTA Button

struct OnboardingCTAButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.r(.headline, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            isEnabled
                                ? AppColors.brand
                                : AppColors.brand.opacity(0.35)
                        )
                )
        }
        .disabled(!isEnabled)
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingView { }
}
