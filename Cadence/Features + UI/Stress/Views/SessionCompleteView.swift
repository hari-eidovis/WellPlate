//
//  SessionCompleteView.swift
//  WellPlate
//
//  Shared post-session summary, reusable across all reset types.
//  Watch bolt-on ready: HR delta section is nil-gated.
//

import SwiftUI

struct SessionCompleteView: View {

    let type: ResetType
    let durationSeconds: Int
    let onDone: () -> Void

    // Watch bolt-on: populate these when Watch ships
    var preHeartRate: Double? = nil
    var postHeartRate: Double? = nil

    @State private var checkmarkAnimated = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(type.accentColor.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(type.accentColor)
                    .scaleEffect(checkmarkAnimated ? 1 : 0.4)
                    .opacity(checkmarkAnimated ? 1 : 0)
            }
            .padding(.bottom, 28)

            Text("Reset Complete")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Your nervous system just got a reset.")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 40)

            // Duration
            Text("\(durationSeconds)s session")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 6)

            // Watch bolt-on: HR delta section (hidden when nil)
            if let pre = preHeartRate, let post = postHeartRate {
                HStack(spacing: 20) {
                    hrStat(label: "Before", value: "\(Int(pre)) BPM")
                    Image(systemName: "arrow.right")
                        .foregroundColor(.white.opacity(0.4))
                    hrStat(label: "After", value: "\(Int(post)) BPM")
                }
                .padding(.top, 28)
            }

            Spacer()

            // Done button
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(type.accentColor)
                    )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .onAppear {
            // L1 fix: completion haptic omitted — the timer's final phase
            // already provides the completion cue.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                checkmarkAnimated = true
            }
        }
    }

    private func hrStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}
