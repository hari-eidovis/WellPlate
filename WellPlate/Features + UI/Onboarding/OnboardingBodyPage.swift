import SwiftUI

/// Screen 3: Weight & height collection with wheel pickers and unit toggles.
struct OnboardingBodyPage: View {
    @Binding var weightValue: Double
    @Binding var heightValue: Double
    @Binding var weightUnit: WeightUnit
    @Binding var heightUnit: HeightUnit

    var onContinue: () -> Void

    @State private var animate = false

    // Picker ranges
    private var weightRange: [Int] {
        switch weightUnit {
        case .kg:  return Array(30...200)
        case .lbs: return Array(66...440)
        }
    }

    private var heightRange: [Int] {
        switch heightUnit {
        case .cm: return Array(100...250)
        case .ft: return Array(100...250) // still store cm internally; display converted
        }
    }

    // Current display integer
    private var displayWeightInt: Int {
        switch weightUnit {
        case .kg:  return Int(weightValue)
        case .lbs: return Int(weightValue * 2.20462)
        }
    }

    private var displayHeightInt: Int {
        Int(heightValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            // Illustration
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.08))
                    .frame(width: 140, height: 140)

                Image(systemName: "figure.stand")
                    .font(.system(size: 52))
                    .foregroundStyle(AppColors.brand.opacity(0.7))
                    .symbolRenderingMode(.hierarchical)

                // Measurement tape icon
                Image(systemName: "ruler.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.brand.opacity(0.4))
                    .offset(x: 55, y: -50)
                    .rotationEffect(.degrees(45))

                Image(systemName: "scalemass.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.brand.opacity(0.35))
                    .offset(x: -50, y: -50)
            }
            .scaleEffect(animate ? 1 : 0.7)
            .opacity(animate ? 1 : 0)
            .padding(.bottom, 24)

            // Title
            VStack(spacing: 8) {
                Text("Let's get your basics")
                    .font(.r(.title2, .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("This helps us calculate your nutrition goals.")
                    .font(.r(.body, .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 15)
            .padding(.bottom, 28)

            // Weight picker card
            BodyMetricCard(
                title: "Weight",
                icon: "scalemass.fill",
                value: displayWeightInt,
                unit: weightUnit.rawValue,
                range: weightRange,
                animate: animate
            ) { newVal in
                switch weightUnit {
                case .kg:  weightValue = Double(newVal)
                case .lbs: weightValue = Double(newVal) / 2.20462
                }
            } unitToggle: {
                UnitToggle(
                    options: WeightUnit.allCases.map(\.rawValue),
                    selected: weightUnit.rawValue
                ) { raw in
                    if let unit = WeightUnit(rawValue: raw) {
                        let currentKg = weightValue
                        weightUnit = unit
                        // Keep same kg, display will update
                        weightValue = currentKg
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Height picker card
            BodyMetricCard(
                title: "Height",
                icon: "ruler.fill",
                value: displayHeightInt,
                unit: "cm",
                range: heightRange,
                animate: animate
            ) { newVal in
                heightValue = Double(newVal)
            } unitToggle: {
                // For simplicity, height stays in cm
                // Future: add ft/in toggle
                EmptyView()
            }
            .padding(.horizontal, 24)

            Spacer()

            // CTA
            OnboardingCTAButton("Continue") {
                onContinue()
            }
            .opacity(animate ? 1 : 0)

            Spacer().frame(height: 16)
        }
        .onAppear {
            // Apply defaults if 0
            if weightValue == 0 { weightValue = 70 }
            if heightValue == 0 { heightValue = 170 }

            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                animate = true
            }
        }
    }
}

// MARK: - Body Metric Card

private struct BodyMetricCard<Toggle: View>: View {
    let title: String
    let icon: String
    let value: Int
    let unit: String
    let range: [Int]
    let animate: Bool
    let onValueChanged: (Int) -> Void
    @ViewBuilder let unitToggle: Toggle

    @State private var selectedValue: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.brand)

                Text(title)
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                unitToggle
            }

            // Value display + picker
            HStack(spacing: 0) {
                Spacer()

                // Big number display
                VStack(spacing: 2) {
                    Text("\(selectedValue)")
                        .font(.r(42, .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(unit)
                        .font(.r(.caption, .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                // Stepper
                VStack(spacing: 8) {
                    Button {
                        adjustValue(by: 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.brand)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(AppColors.brand.opacity(0.1))
                            )
                    }

                    Button {
                        adjustValue(by: -1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.brand)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(AppColors.brand.opacity(0.1))
                            )
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(height: 90)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .opacity(animate ? 1 : 0)
        .offset(y: animate ? 0 : 20)
        .onAppear {
            selectedValue = value
        }
        .onChange(of: value) { _, newValue in
            selectedValue = newValue
        }
    }

    private func adjustValue(by delta: Int) {
        HapticService.selectionChanged()
        let newVal = selectedValue + delta
        guard range.contains(newVal) else { return }
        withAnimation(.spring(response: 0.25)) {
            selectedValue = newVal
        }
        onValueChanged(newVal)
    }
}

// MARK: - Unit Toggle

private struct UnitToggle: View {
    let options: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    HapticService.selectionChanged()
                    onSelect(option)
                } label: {
                    Text(option.uppercased())
                        .font(.r(.caption2, .semibold))
                        .foregroundStyle(
                            selected == option ? .white : AppColors.textSecondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selected == option
                                ? AnyShape(Capsule()).fill(AppColors.brand)
                                : AnyShape(Capsule()).fill(Color.clear)
                        )
                }
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemBackground))
        )
    }
}
