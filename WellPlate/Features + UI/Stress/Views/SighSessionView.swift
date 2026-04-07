//
//  SighSessionView.swift
//  WellPlate
//
//  Physiological sigh breathing guide: 3 cycles of
//  [inhale × 2 → long exhale]. ~33 seconds total.
//

import SwiftUI
import SwiftData

struct SighSessionView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var timer = InterventionTimer()
    @State private var sessionStart: Date = .now
    @State private var showComplete = false

    // 3 cycles × 3 phases = 9 phases total
    private var phases: [InterventionPhase] {
        var result: [InterventionPhase] = []
        for _ in 0..<3 {
            result.append(InterventionPhase(name: "First inhale",  duration: 1.5, hapticOnStart: .snap))
            result.append(InterventionPhase(name: "Second inhale", duration: 1.5, hapticOnStart: .snap))
            result.append(InterventionPhase(name: "Long exhale",   duration: 8.0, hapticOnStart: .softPulse(count: 4, interval: 2.0)))
        }
        return result
    }

    private var isExhale: Bool {
        timer.currentPhaseIndex % 3 == 2
    }

    // Circle scale: small during inhale phases, large during exhale
    private var circleScale: Double {
        if isExhale {
            // Contracts from 1.0 → 0.55 as exhale progresses
            return 1.0 - (timer.phaseProgress * 0.45)
        } else {
            // Expands from 0.55 → 1.0 as inhale progresses
            let baseScale: Double = timer.currentPhaseIndex % 3 == 0 ? 0.55 : 0.78
            return baseScale + (timer.phaseProgress * (1.0 - baseScale))
        }
    }

    private var cycleNumber: Int { (timer.currentPhaseIndex / 3) + 1 }

    var body: some View {
        ZStack {
            Color(hue: 0.67, saturation: 0.15, brightness: 0.08).ignoresSafeArea()

            if showComplete {
                SessionCompleteView(
                    type: .sigh,
                    durationSeconds: Int(Date().timeIntervalSince(sessionStart))
                ) {
                    dismiss()
                }
                .transition(.opacity)
            } else {
                sessionContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !showComplete {
                    Button("Cancel") {
                        saveSession(completed: false)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            sessionStart = .now
            timer.onComplete = {
                saveSession(completed: true)
                withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
            }
            timer.start(phases: phases)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timer.cancel()
        }
    }

    private var sessionContent: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.indigo.opacity(0.15), lineWidth: 1)
                    .frame(width: 260, height: 260)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.indigo.opacity(0.6), Color.indigo.opacity(0.2)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 130
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(circleScale)
                    .animation(.easeInOut(duration: 0.08), value: circleScale)

                VStack(spacing: 4) {
                    Text(timer.currentPhaseName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: timer.currentPhaseIndex)
                }
            }

            Text("Cycle \(min(cycleNumber, 3)) of 3")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 32)

            Spacer()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 3)
                    Capsule()
                        .fill(Color.indigo.opacity(0.7))
                        .frame(width: geo.size.width * timer.totalProgress, height: 3)
                        .animation(.linear(duration: 0.05), value: timer.totalProgress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    private func saveSession(completed: Bool) {
        let session = InterventionSession(
            resetType: .sigh,
            startedAt: sessionStart,
            durationSeconds: Int(Date().timeIntervalSince(sessionStart)),
            completed: completed
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}
