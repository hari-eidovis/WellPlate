//
//  StressFactorCardView.swift
//  WellPlate
//
//  Created on 21.02.2026.
//

import SwiftUI

struct StressFactorCardView: View {

    let factor: StressFactorResult
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: {
                HapticService.impact(.light)
                onTap()
            }) { cardContent }
                .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon 44×44
            Image(systemName: factor.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(factor.accentColor)
                .frame(width: 44, height: 44)
                .background(factor.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                // Title row: name + score pill + chevron
                HStack(spacing: 6) {
                    Text(factor.title)
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(Int(factor.score))/25")
                        .font(.r(.caption, .bold))
                        .foregroundColor(factor.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(factor.accentColor.opacity(0.12)))

                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }

                // Progress bar — 8pt capsule
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        Capsule()
                            .fill(factor.accentColor)
                            .frame(width: max(0, geo.size.width * factor.progress), height: 8)
                    }
                }
                .frame(height: 8)

                // Status text
                Text(factor.statusText)
                    .font(.r(.caption, .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Inline tip
                if !inlineTip.isEmpty {
                    Text(inlineTip)
                        .font(.r(.caption2, .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var inlineTip: String {
        switch factor.title {
        case "Exercise":
            return factor.score < 10
                ? "A 20-min walk can significantly reduce stress hormones."
                : "Keep moving — your activity level is helping!"
        case "Sleep":
            return factor.score < 10
                ? "Aim for 7–9 hours tonight. Avoid screens before bed."
                : "Your sleep is contributing to lower stress."
        case "Diet":
            return factor.score < 10
                ? "Try adding more protein and fiber to your meals today."
                : "Good nutritional balance today!"
        case "Screen Time":
            return factor.score > 15
                ? "Take a break from your phone — try reading or a short walk."
                : "Nice screen time management!"
        default:
            return ""
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 10, y: 4)
    }
}
