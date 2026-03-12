import SwiftUI

/// Screen 2: Conversational name input.
struct OnboardingNamePage: View {
    @Binding var name: String
    var onContinue: () -> Void

    @FocusState private var isFocused: Bool
    @State private var animate = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Illustration
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.08))
                    .frame(width: 160, height: 160)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.brand.opacity(0.7))
                    .symbolRenderingMode(.hierarchical)

                // Decorative leaf
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.brand.opacity(0.5))
                    .offset(x: 60, y: -60)
                    .rotationEffect(.degrees(30))

                Image(systemName: "leaf.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.brand.opacity(0.35))
                    .offset(x: -55, y: -55)
                    .rotationEffect(.degrees(-20))
            }
            .scaleEffect(animate ? 1.0 : 0.7)
            .opacity(animate ? 1 : 0)
            .padding(.bottom, 40)

            // Title
            VStack(spacing: 8) {
                Text("What's your name?")
                    .font(.r(.title2, .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Let's personalize your wellness journey.")
                    .font(.r(.body, .regular))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 15)
            .padding(.bottom, 32)

            // Text field
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.brand.opacity(0.6))

                TextField("Enter your name", text: $name)
                    .font(.r(.body, .medium))
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.continue)
                    .onSubmit {
                        if isValid { onContinue() }
                    }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isFocused ? AppColors.brand.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .padding(.horizontal, 24)
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 20)

            Spacer()
            Spacer()

            // CTA
            OnboardingCTAButton("Continue", isEnabled: isValid) {
                onContinue()
            }
            .opacity(animate ? 1 : 0)

            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                animate = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isFocused = true
            }
        }
    }
}
