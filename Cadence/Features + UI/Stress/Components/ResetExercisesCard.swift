//
//  ResetExercisesCard.swift
//  Cadence
//
//  Inline "Quick Reset" dropdown for the Stress tab. Collapsed it shows a
//  prompt with a chevron; tapping the header expands it to list the acute
//  reset exercises, each styled like a Home dashboard tile. Selecting one
//  launches its full-screen session via a fullScreenCover (so the tab bar
//  stays hidden and the session's Cancel toolbar has a NavigationStack).
//

import SwiftUI

struct ResetExercisesCard: View {

    @State private var isExpanded = false
    @State private var activeSession: ResetType?

    var body: some View {
        VStack(spacing: 12) {
            header

            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(ResetType.allCases) { type in
                        ResetExerciseTile(type: type) {
                            HapticService.impact(.light)
                            activeSession = type
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .fullScreenCover(item: $activeSession) { type in
            NavigationStack {
                sessionView(for: type)
            }
        }
    }

    // MARK: - Header (expand / collapse)

    private var header: some View {
        Button {
            HapticService.impact(.light)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.teal)

                Text("Try a Quick Reset")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.teal.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.teal.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick Reset exercises")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand to choose an exercise")
    }

    // MARK: - Session routing

    @ViewBuilder
    private func sessionView(for type: ResetType) -> some View {
        switch type {
        case .pmr:       PMRSessionView()
        case .sigh:      SighSessionView()
        case .grounding: GroundingSessionView()
        }
    }
}

// MARK: - Reset Exercise Tile (Home dashboard card style)

private struct ResetExerciseTile: View {
    let type: ResetType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(type.accentColor.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(type.accentColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(type.subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.card)
                    .appShadow(radius: 14, y: 5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.title). \(type.subtitle)")
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ResetExercisesCard()
            .padding(20)
    }
    .background(Color(.systemGroupedBackground))
}
