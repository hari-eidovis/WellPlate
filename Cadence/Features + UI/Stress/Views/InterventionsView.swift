//
//  InterventionsView.swift
//  WellPlate
//
//  Sheet root listing acute reset exercises. NavigationStack pushes
//  into full-screen session views (PMR, Sigh).
//

import SwiftUI

struct InterventionsView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection
                    resetCards
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Resets")
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Resets")
                .font(.r(.title2, .bold))
            Text("Science-backed exercises to activate your parasympathetic nervous system in under 2 minutes.")
                .font(.r(.footnote, .regular))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetCards: some View {
        VStack(spacing: 12) {
            ForEach(ResetType.allCases) { type in
                NavigationLink {
                    sessionView(for: type)
                } label: {
                    ResetCardRow(type: type)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func sessionView(for type: ResetType) -> some View {
        switch type {
        case .pmr:  PMRSessionView()
        case .sigh: SighSessionView()
        }
    }
}

// MARK: - Reset Card Row

private struct ResetCardRow: View {
    let type: ResetType

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(type.accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: type.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(type.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(.r(.body, .semibold))
                    .foregroundColor(.primary)
                Text(type.subtitle)
                    .font(.r(.caption, .regular))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
    }
}
