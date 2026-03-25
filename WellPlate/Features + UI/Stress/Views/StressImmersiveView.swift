//
//  StressImmersiveView.swift
//  WellPlate
//

import SwiftUI

// MARK: - Data Transfer Types

struct ImmersiveFactorItem {
    let factor: StressFactorResult
    /// nil for Screen Time — taps open .screenTimeDetail directly.
    let sheet: StressSheet?
}

struct ImmersiveVitalRow {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let sheet: StressSheet
}

// MARK: - StressImmersiveView

struct StressImmersiveView: View {

    let score: Double
    let level: StressLevel
    let factorItems: [ImmersiveFactorItem]
    let vitalRows: [ImmersiveVitalRow]
    let percentile: Int
    let onFactorTap: (StressSheet) -> Void
    let onVitalTap: (StressSheet) -> Void

    @State private var orbPulse = false
    @State private var auraAngle: Double = 0
    @State private var appearCards = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // ── Dynamic Aura Background ─────────────────────────────
            auraBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                // ── Top floating stat cards ───────────────────
                topStatsRow
                    .padding(.horizontal, 28)

                Spacer()

                // ── Central orb + score ───────────────────────
                ZStack {
                    ambientOrb
                    scoreCenterView
                }

                Text("Your biological stress level is currently \(Int(score)), which is categorized as \(level.label).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                Spacer()

                // ── Steps card (left-aligned) ─────────────────
                HStack {
                    stepsCard
                    Spacer()
                    if let hrv = vitalRows.first(where: { $0.label == "HRV" }) {
                        hrvCard(for: hrv)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)

                // ── Bottom factor row ─────────────────────────
                factorRow
                    .padding(.horizontal, 20)

                // ── Insights ──────────────────────────────────
                insightsButton
                    .padding(.top, 10)
                    .padding(.bottom, 32)
            }
            .opacity(appearCards ? 1 : 0)
            .scaleEffect(appearCards ? 1 : 0.95)
            .animation(.spring(response: 0.7, dampingFraction: 0.75), value: appearCards)
            .onAppear {
                guard !reduceMotion else {
                    appearCards = true
                    return
                }
                appearCards = true
            }
        }
    }

    // MARK: - Dynamic Aura Background

    private var auraBackground: some View {
        ZStack {
            Color(.systemGroupedBackground)
            
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(level.color.opacity(0.35))
                        .frame(width: geo.size.width * 1.2, height: geo.size.width * 1.2)
                        .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.1)
                        .rotationEffect(.degrees(auraAngle))
                        .blur(radius: 80)
                    
                    Circle()
                        .fill(level.color.opacity(0.25))
                        .frame(width: geo.size.width * 1.4, height: geo.size.width * 1.4)
                        .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.3)
                        .rotationEffect(.degrees(-auraAngle * 0.8))
                        .blur(radius: 100)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            
            Color.clear.background(.ultraThinMaterial)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                auraAngle = 360
            }
        }
    }

    // MARK: - Ambient Orb

    private var ambientOrb: some View {
        ZStack {
            // Outer soft halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [level.color.opacity(0.13), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 190
                    )
                )
                .frame(width: 370, height: 370)
                .scaleEffect(orbPulse ? 1.04 : 0.97)
                .animation(
                    reduceMotion ? nil :
                        .easeInOut(duration: 3.5).repeatForever(autoreverses: true),
                    value: orbPulse
                )

            // Main orb
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            level.color.opacity(0.8),
                            level.color.opacity(0.3),
                            level.color.opacity(0.9),
                            level.color.opacity(0.4),
                            level.color.opacity(0.8)
                        ],
                        center: .center,
                        startAngle: .degrees(auraAngle),
                        endAngle: .degrees(auraAngle + 360)
                    )
                )
                .frame(width: 276, height: 276)
                .blur(radius: 8) // soften angular edges
                .overlay(
                    Circle()
                        .stroke(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                )
                .overlay(
                    Circle()
                        .stroke(level.color.opacity(0.3), lineWidth: 8)
                        .blur(radius: 4)
                        .clipShape(Circle())
                )
                .scaleEffect(orbPulse ? 1.02 : 0.99)
                .animation(
                    reduceMotion ? nil :
                        .easeInOut(duration: 3.5).repeatForever(autoreverses: true),
                    value: orbPulse
                )
        }
        .onAppear {
            guard !reduceMotion else { return }
            orbPulse = true
        }
    }

    // MARK: - Score Center

    private var scoreCenterView: some View {
        VStack(spacing: 5) {
            Text("\(Int(score))")
                .font(.system(size: 82, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [level.color, level.color.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                )
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(level.label.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(level.color)
                .tracking(2.2)

            Text(synchronyText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private var synchronyText: String {
        switch level {
        case .excellent: return "Bio-Sync Active"
        case .good:      return "Vitals Stable"
        case .moderate:  return "Moderate Load Detected"
        case .high:      return "Elevated Stress Signals"
        case .veryHigh:  return "High Stress Detected"
        }
    }

    // MARK: - Top Stats

    private var topStatsRow: some View {
        HStack(alignment: .top) {
            // Heart rate card
            if let hr = vitalRows.first(where: { $0.label == "HEART RATE" }) {
                Button { onVitalTap(hr.sheet) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.pink)
                        Text(hr.value)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Sleep card
            if let sl = vitalRows.first(where: { $0.label == "SLEEP" }) {
                Button { onVitalTap(sl.sheet) } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hue: 0.68, saturation: 0.55, brightness: 0.75))
                            Text(sl.value)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("DEEP REST")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Steps Card

    private var stepsCard: some View {
        let activity = vitalRows.first(where: { $0.label == "ACTIVITY" })
        let stepsText = activity.map { stepsOnly($0.value) } ?? "—"

        return Button {
            if let a = activity { onVitalTap(a.sheet) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hue: 0.55, saturation: 0.55, brightness: 0.60))
                VStack(alignment: .leading, spacing: 1) {
                    Text(stepsText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("STEPS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
            )
        }
        .buttonStyle(.plain)
    }

    /// Extracts the steps part from "8,245 steps · 320 kcal" → "8,245"
    private func stepsOnly(_ statusText: String) -> String {
        let part = statusText.components(separatedBy: " · ").first ?? statusText
        return part
            .replacingOccurrences(of: " steps", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func hrvCard(for hrv: ImmersiveVitalRow) -> some View {
        Button {
            onVitalTap(hrv.sheet)
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: hrv.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(hrv.iconColor)
                    Text(hrv.value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                Text("HRV")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Factor Row

    private var factorRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(factorItems.prefix(3).enumerated()), id: \.offset) { _, item in
                Button {
                    HapticService.impact(.light)
                    onFactorTap(item.sheet ?? .screenTimeDetail)
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: item.factor.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(item.factor.accentColor)
                        Text(factorStatusLabel(item.factor))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 32, x: 0, y: 16)
        )
    }

    private func factorStatusLabel(_ factor: StressFactorResult) -> String {
        let c = factor.stressContribution
        if c <= 5  { return "OPTIMAL" }
        if c <= 13 { return "LOW" }
        return "FOCUS"
    }

    // MARK: - Insights

    private var insightsButton: some View {
        Button {
            // Future: open insights sheet
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("INSIGHTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1.4)
            }
        }
        .buttonStyle(.plain)
    }
}
