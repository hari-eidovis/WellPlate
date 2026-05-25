//
//  MockModeDebugCard.swift
//  WellPlate
//
//  Unified mock mode card for Profile. Replaces both NutritionSourceDebugCard
//  and MockDataDebugCard. Single toggle controls API mock + data injection.
//

#if DEBUG
import SwiftUI

/// IMPORTANT: ProfileView must NOT have a separate onChange(of: mockModeEnabled) handler —
/// the onToggle callback is the single source of truth for flag + data changes.
struct MockModeDebugCard: View {
    @Binding var isMockMode: Bool
    let hasGroqAPIKey: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("Mock Mode")
                    .font(.r(.headline, .semibold))
                Spacer()
                Text(isMockMode ? "Active" : "Off")
                    .font(.r(.caption2, .semibold))
                    .foregroundStyle(isMockMode ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isMockMode ? Color.green : Color.secondary).opacity(0.15))
                    )
            }

            Toggle("Enable Mock Mode", isOn: $isMockMode)
                .font(.r(.subheadline, .semibold))
                .tint(AppColors.brand)
                .onChange(of: isMockMode) { _, newValue in
                    onToggle(newValue)
                }

            if isMockMode {
                Text("All features use mock data. 30 days of food logs, wellness data, stress readings, HealthKit metrics, symptoms, fasting sessions, supplements, and journal entries.")
                    .font(.r(.caption, .medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(hasGroqAPIKey ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(hasGroqAPIKey ? "GROQ_API_KEY detected" : "GROQ_API_KEY missing — nutrition AI unavailable")
                        .font(.r(.caption, .medium))
                        .foregroundStyle(hasGroqAPIKey ? Color.green : Color.orange)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }
}
#endif
