//
//  ScreenTimeInputSheet.swift
//  WellPlate
//
//  Created on 21.02.2026.
//

import SwiftUI

struct ScreenTimeInputSheet: View {

    @Binding var hours: Double
    var autoDetectedHours: Double?
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let quickPicks: [Double] = [1, 2, 3, 4, 6]

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer().frame(height: 8)

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                        )

                    Text("Today's Screen Time")
                        .font(.r(.title3, .bold))

                    Text("How long did you use your phone today?")
                        .font(.r(.subheadline, .regular))
                        .foregroundColor(.secondary)
                }

                // Large hour display
                Text(String(format: "%.1f hrs", hours))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .contentTransition(.numericText())
                    .animation(.snappy, value: hours)

                // Slider
                VStack(spacing: 6) {
                    Slider(value: $hours, in: 0...12, step: 0.5)
                        .tint(.cyan)

                    HStack {
                        Text("0h")
                        Spacer()
                        Text("12h")
                    }
                    .font(.r(.caption, .medium))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)

                // Quick-pick pills
                HStack(spacing: 10) {
                    ForEach(quickPicks, id: \.self) { value in
                        Button {
                            HapticService.impact(.rigid)
                            withAnimation(.snappy) { hours = value }
                        } label: {
                            Text("\(Int(value))h")
                                .font(.r(.subheadline, .semibold))
                                .foregroundColor(hours == value ? .white : .cyan)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(hours == value ? .cyan : Color.cyan.opacity(0.12))
                                )
                        }
                    }
                }

                Spacer()

                // Save button
                Button {
                    HapticService.notify(.success)
                    onSave()
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.r(.headline, .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .padding(.horizontal, 8)

                // Auto-detected info or manual label
                Group {
                    if let autoHours = autoDetectedHours {
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.caption2)
                            Text(String(format: "Auto-detected: %.0fh", autoHours))
                                .font(.r(.caption, .medium))
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.cyan.opacity(0.1)))
                    } else {
                        Text("Manual entry · auto-detection requires Screen Time permission")
                            .font(.r(.caption2, .regular))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    Text("Parent")
        .sheet(isPresented: .constant(true)) {
            ScreenTimeInputSheet(hours: .constant(3.5), autoDetectedHours: 2.0) { }
        }
}
