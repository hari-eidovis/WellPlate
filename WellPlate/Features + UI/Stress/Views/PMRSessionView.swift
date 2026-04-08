//
//  PMRSessionView.swift
//  WellPlate
//
//  Full-screen dark PMR (progressive muscle relaxation) exercise.
//  8 muscle groups, tense 4s → release 3.5s, ~60 seconds total.
//

import SwiftUI
import SwiftData

struct PMRSessionView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var timer = InterventionTimer()
    @State private var sessionStart: Date = .now
    @State private var showComplete = false

    private let muscleGroups = [
        "Hands & Forearms",
        "Shoulders",
        "Jaw & Face",
        "Chest",
        "Abdomen",
        "Glutes",
        "Thighs",
        "Calves & Feet"
    ]

    private var phases: [InterventionPhase] {
        muscleGroups.flatMap { group in [
            InterventionPhase(name: "Tense — \(group)", duration: 4.0, hapticOnStart: .rise),
            InterventionPhase(name: "Release",          duration: 3.5, hapticOnStart: .snap)
        ]}
    }

    private var totalGroups: Int { muscleGroups.count }
    private var completedGroups: Int { timer.currentPhaseIndex / 2 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showComplete {
                SessionCompleteView(
                    type: .pmr,
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

            // Start Live Activity before timer (so onPhaseStart can update it)
            let sessionPhases = phases
            let totalDuration = sessionPhases.map(\.duration).reduce(0, +)
            ActivityManager.shared.startBreathingActivity(
                sessionName: "PMR",
                totalSteps: muscleGroups.count,
                stepLabel: "Group",
                firstPhaseName: sessionPhases[0].name,
                firstPhaseEndDate: Date().addingTimeInterval(sessionPhases[0].duration),
                totalSessionDuration: totalDuration
            )

            // PMR: 2 phases per muscle group (tense + release)
            timer.onPhaseStart = { phase in
                let groupNumber = (timer.currentPhaseIndex / 2) + 1
                ActivityManager.shared.updateBreathingActivity(
                    phaseName: phase.name,
                    phaseEndDate: Date().addingTimeInterval(phase.duration),
                    currentStep: groupNumber,
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

            VStack(spacing: 16) {
                let isTense = timer.currentPhaseIndex % 2 == 0
                Text(isTense ? "TENSE" : "RELEASE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2.5)
                    .foregroundColor(isTense ? .teal : .white.opacity(0.45))

                Text(muscleGroups[min(completedGroups, muscleGroups.count - 1)])
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: timer.currentPhaseIndex)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: timer.phaseProgress)
                        .stroke(isTense ? Color.teal : Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: timer.phaseProgress)
                }
                .frame(width: 80, height: 80)
            }
            .padding(.horizontal, 40)

            Spacer()

            progressDots
                .padding(.bottom, 60)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalGroups, id: \.self) { i in
                Circle()
                    .fill(i < completedGroups ? Color.teal : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .scaleEffect(i == completedGroups ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3), value: completedGroups)
            }
        }
    }

    private func saveSession(completed: Bool) {
        let session = InterventionSession(
            resetType: .pmr,
            startedAt: sessionStart,
            durationSeconds: Int(Date().timeIntervalSince(sessionStart)),
            completed: completed
        )
        modelContext.insert(session)
        try? modelContext.save()
    }
}
