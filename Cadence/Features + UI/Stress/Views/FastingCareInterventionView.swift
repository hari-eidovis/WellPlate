//
//  FastingCareInterventionView.swift
//  Cadence
//
//  Soft-block screen shown when a user fails the fasting eligibility gate
//  (SCOFF ≥2 positives or demographic disqualification). Non-clinical copy
//  + US-based resources + caveat for non-US users + Re-take screening CTA.
//
//  Phase 1.1 of fasting-v1 blueprint.
//

import SwiftUI

struct FastingCareInterventionView: View {

    @Environment(\.dismiss) private var dismiss

    /// Triggered when user taps "Re-take screening". Caller decides what to do
    /// — typically: route back to the SCOFF step with fresh blank state.
    var onRetake: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    headerSection
                    resourceLinks
                    healthcareProviderReminder
                    footerCaveat
                    retakeButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.r(.body, .medium))
                        .foregroundColor(AppColors.brand)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.brand.opacity(0.22), AppColors.brand.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
            }
            .accessibilityHidden(true)

            Text("Fasting may not be the best fit for your current wellness journey right now")
                .font(.r(.title3, .bold))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)

            Text("Your answers suggest your needs may go beyond what Cadence is built for. Cadence focuses on general wellness — not clinical care. The resources below are designed for people who may benefit from specialized support.")
                .font(.r(.subheadline, .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Resource Links

    private var resourceLinks: some View {
        VStack(spacing: 12) {
            resourceLink(
                title: "National Alliance for Eating Disorders",
                subtitle: "Find help & treatment resources",
                systemImage: "person.2.fill",
                urlString: "https://allianceforeatingdisorders.com/find-help",
                accessibilityName: "National Alliance for Eating Disorders"
            )
            resourceLink(
                title: "988 Suicide & Crisis Lifeline",
                subtitle: "24/7 confidential support",
                systemImage: "phone.fill",
                urlString: "https://988lifeline.org",
                accessibilityName: "988 Suicide and Crisis Lifeline"
            )
        }
    }

    @ViewBuilder
    private func resourceLink(
        title: String,
        subtitle: String,
        systemImage: String,
        urlString: String,
        accessibilityName: String
    ) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                resourceRow(title: title, subtitle: subtitle, systemImage: systemImage, isExternal: true)
            }
            .accessibilityLabel("Opens \(accessibilityName) website")
            .accessibilityAddTraits(.isLink)
        }
    }

    private func resourceRow(title: String, subtitle: String, systemImage: String, isExternal: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.brand.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.r(.footnote, .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if isExternal {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.card)
                .appShadow(radius: 12, y: 4)
        )
    }

    // MARK: - Healthcare Provider Reminder (no link)

    private var healthcareProviderReminder: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 40, height: 40)
                Image(systemName: "stethoscope")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Talk to a healthcare provider")
                    .font(.r(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                Text("They can help you find what's right for you.")
                    .font(.r(.footnote, .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.card)
                .appShadow(radius: 12, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Talk to a healthcare provider. They can help you find what's right for you.")
    }

    // MARK: - Footer Caveat

    private var footerCaveat: some View {
        let caveat = "Resources listed are US-based. If you're outside the US, please contact your local mental health services or healthcare provider."
        return Text(caveat)
            .font(.r(.caption2, .regular))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .accessibilityLabel(caveat)
    }

    // MARK: - Retake CTA

    private var retakeButton: some View {
        Button {
            HapticService.impact(.light)
            onRetake()
        } label: {
            Text("Re-take screening")
                .font(.r(.body, .semibold))
                .foregroundStyle(AppColors.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColors.brand, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityHint("Returns to the wellness screening with blank answers.")
    }
}

#Preview {
    FastingCareInterventionView(onRetake: {})
}
