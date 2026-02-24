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
            Button(action: onTap) { cardContent }
                .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon + title + score
            HStack {
                Image(systemName: factor.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(factor.accentColor)
                    .frame(width: 28, height: 28)
                    .background(factor.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(factor.title)
                    .font(.r(.subheadline, .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(String(format: "%.0f", factor.score))
                    .font(.r(15, .bold))
                    .foregroundColor(factor.accentColor)
                +
                Text(" / 25")
                    .font(.r(.caption, .medium))
                    .foregroundColor(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(factor.accentColor)
                        .frame(width: max(0, geo.size.width * factor.progress), height: 6)
                }
            }
            .frame(height: 6)

            // Status + detail text
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.statusText)
                    .font(.r(.caption, .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(factor.detailText)
                    .font(.r(.caption2, .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemBackground))
            .appShadow(radius: 10, y: 4)
    }
}

// MARK: - Preview

//#Preview {
//    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
//        StressFactorCardView(
//            factor: StressFactorResult(
//                title: "Exercise", score: 8.2, maxScore: 25,
//                icon: "figure.run",
//                statusText: "7,245 steps · 312 kcal",
//                detailText: "Great activity level!"
//            )
//        )
//        StressFactorCardView(
//            factor: StressFactorResult(
//                title: "Screen Time", score: 18, maxScore: 25,
//                icon: "iphone",
//                statusText: "5.5 hours today",
//                detailText: "Consider reducing screen time"
//            ),
//            onTap: { }
//        )
//    }
//    .padding()
//}
