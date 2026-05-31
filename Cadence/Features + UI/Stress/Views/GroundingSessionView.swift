//
//  GroundingSessionView.swift
//  Cadence
//
//  5-4-3-2-1 sensory grounding: name 5 things you see, 4 hear,
//  3 feel, 2 smell, 1 taste. Anchors attention to the present
//  moment to interrupt anxiety/rumination. ~60 seconds total.
//

import SwiftUI
import SwiftData

struct GroundingSessionView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var timer = InterventionTimer()
    @State private var sessionStart: Date = .now
    @State private var showComplete = false

    private struct Sense {
        let count: Int
        let verb: String     // "SEE"
        let prompt: String   // "things you can see around you"
        let duration: TimeInterval
    }

    private let senses: [Sense] = [
        Sense(count: 5, verb: "SEE",   prompt: "things you can see around you",        duration: 15.0),
        Sense(count: 4, verb: "HEAR",  prompt: "sounds you can hear right now",        duration: 13.0),
        Sense(count: 3, verb: "FEEL",  prompt: "things you can physically feel",       duration: 11.0),
        Sense(count: 2, verb: "SMELL", prompt: "scents you can notice",                duration: 9.0),
        Sense(count: 1, verb: "TASTE", prompt: "taste you can detect, or imagine one", duration: 7.0)
    ]

    private var phases: [InterventionPhase] {
        senses.map { sense in
            InterventionPhase(
                name: "\(sense.count) \(sense.prompt)",
                duration: sense.duration,
                hapticOnStart: .snap
            )
        }
    }

    private var currentSense: Sense {
        senses[min(timer.currentPhaseIndex, senses.count - 1)]
    }

    private var totalSteps: Int { senses.count }
    private var completedSteps: Int { timer.currentPhaseIndex }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showComplete {
                SessionCompleteView(
                    type: .grounding,
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
                        ActivityManager.shared.endBreathingActivity()
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

            let sessionPhases = phases
            let totalDuration = sessionPhases.map(\.duration).reduce(0, +)
            ActivityManager.shared.startBreathingActivity(
                sessionName: "Grounding",
                totalSteps: senses.count,
                stepLabel: "Sense",
                firstPhaseName: sessionPhases[0].name,
                firstPhaseEndDate: Date().addingTimeInterval(sessionPhases[0].duration),
                totalSessionDuration: totalDuration
            )

            timer.onPhaseStart = { phase in
                ActivityManager.shared.updateBreathingActivity(
                    phaseName: phase.name,
                    phaseEndDate: Date().addingTimeInterval(phase.duration),
                    currentStep: timer.currentPhaseIndex + 1,
                    totalProgress: timer.totalProgress
                )
            }

            timer.onComplete = {
                saveSession(completed: true)
                ActivityManager.shared.endBreathingActivity()
                withAnimation(.easeIn(duration: 0.3)) { showComplete = true }
            }
            timer.start(phases: sessionPhases)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timer.cancel()
        }
    }

    private var sessionContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Text("NOTICE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2.5)
                    .foregroundColor(.mint)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: timer.phaseProgress)
                        .stroke(
                            Color.mint.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: timer.phaseProgress)

                    Text("\(currentSense.count)")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: currentSense.count)
                }
                .frame(width: 180, height: 180)

                Text(currentSense.verb)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: timer.currentPhaseIndex)

                Text(currentSense.prompt)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: timer.currentPhaseIndex)
            }

            Spacer()

            progressDots
                .padding(.bottom, 60)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i < completedSteps ? Color.mint : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .scaleEffect(i == completedSteps ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3), value: completedSteps)
            }
        }
    }

    private func saveSession(completed: Bool) {
        let session = InterventionSession(
            resetType: .grounding,
            startedAt: sessionStart,
            durationSeconds: Int(Date().timeIntervalSince(sessionStart)),
            completed: completed
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}
