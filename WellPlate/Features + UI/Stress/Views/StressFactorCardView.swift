//
//  StressFactorCardView.swift
//  WellPlate
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
        HStack(alignment: .center, spacing: 14) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(factor.accentColor.opacity(0.13))
                    .frame(width: 44, height: 44)
                Image(systemName: factor.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(factor.accentColor)
            }

            // Content column
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(factor.title.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    Spacer()
                    // Score pill
                    Text("\(Int(factor.score))/\(Int(factor.maxScore))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(factor.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(factor.accentColor.opacity(0.12)))
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                }

                if factor.hasValidData {
                    // Status text (main info line)
                    Text(factor.statusText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // Slim progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                            Capsule()
                                .fill(factor.accentColor)
                                .frame(width: max(0, geo.size.width * factor.progress), height: 8)
                                .animation(.spring(response: 0.7, dampingFraction: 0.75), value: factor.progress)
                        }
                    }
                    .frame(height: 8)

                    // Tip text
                    if !inlineTip.isEmpty {
                        Text(inlineTip)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.88))
                .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
        )
    }

    private var inlineTip: String {
        switch factor.title {
        case "Exercise":
            return factor.score < 10
                ? "A 20-min walk reduces cortisol significantly."
                : "Activity is keeping your stress low!"
        case "Sleep":
            return factor.score < 10
                ? "Aim for 7–9 hours. Avoid screens an hour before bed."
                : "Your sleep quality is helping."
        case "Diet":
            return factor.score < 10
                ? "Add more protein and fiber to your next meal."
                : "Good nutritional balance today!"
        case "Screen Time":
            return factor.score > 15
                ? "Take a break — try a short walk or reading."
                : "Nice screen time management!"
        default:
            return ""
        }
    }
}
