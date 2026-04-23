//
//  DietDetailView.swift
//  WellPlate
//
//  Created on 25.02.2026.
//

import SwiftUI

struct DietDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let factor: StressFactorResult
    let todayLogs: [FoodLogEntry]

    private var totalCalories: Int { todayLogs.map(\.calories).reduce(0, +) }
    private var totalProtein: Double { todayLogs.map(\.protein).reduce(0, +) }
    private var totalCarbs: Double { todayLogs.map(\.carbs).reduce(0, +) }
    private var totalFat: Double { todayLogs.map(\.fat).reduce(0, +) }
    private var totalFiber: Double { todayLogs.map(\.fiber).reduce(0, +) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        kpiCard
                        macrosCard
                        foodLogCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Diet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - KPI Card

    private var kpiCard: some View {
        HStack(spacing: 20) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.green)
                .frame(width: 56, height: 56)
                .background(Color.green.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.r(.subheadline, .regular))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(todayLogs.isEmpty ? "—" : "\(totalCalories)")
                        .font(.r(36, .heavy))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text("kcal")
                        .font(.r(.title3, .semibold))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 2) {
                (Text(String(format: "%.0f", factor.score))
                    .font(.r(22, .bold))
                    .foregroundColor(factor.accentColor)
                + Text(" /\(Int(factor.maxScore))")
                    .font(.r(.caption, .medium))
                    .foregroundColor(.secondary))
                Text("stress pts")
                    .font(.r(.caption2, .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Macros Card

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Macronutrients")
                .font(.r(.headline, .semibold))

            macroRow(label: "Protein", value: totalProtein, goal: 60, color: .blue)
            macroRow(label: "Fiber",   value: totalFiber,   goal: 25, color: .green)
            macroRow(label: "Carbs",   value: totalCarbs,   goal: 225, color: .orange)
            macroRow(label: "Fat",     value: totalFat,     goal: 65, color: .yellow)
        }
        .padding(20)
        .background(cardBackground)
    }

    private func macroRow(label: String, value: Double, goal: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.r(.subheadline, .medium))
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", value))
                        .font(.r(.subheadline, .semibold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text("/ \(Int(goal))g")
                        .font(.r(.caption, .regular))
                        .foregroundColor(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * min(1, value / goal)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Food Log Card

    private var foodLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Log")
                .font(.r(.headline, .semibold))

            if todayLogs.isEmpty {
                emptyLogState
            } else {
                VStack(spacing: 0) {
                    ForEach(todayLogs) { entry in
                        logRow(entry: entry)
                        if entry.id != todayLogs.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func logRow(entry: FoodLogEntry) -> some View {
        HStack {
            Text(entry.foodName)
                .font(.r(.subheadline, .regular))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            Text("\(entry.calories) kcal")
                .font(.r(.subheadline, .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
    }

    private var emptyLogState: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.3))
            Text("No meals logged today")
                .font(.r(.subheadline, .regular))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .appShadow(radius: 15, y: 5)
    }
}
