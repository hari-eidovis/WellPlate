//
//  MockDataDebugCard.swift
//  WellPlate
//
//  DEBUG-only card for Profile: inject / clear 30 days of mock data.
//

#if DEBUG
import SwiftUI

struct MockDataDebugCard: View {
    @Binding var isInjected: Bool
    let onInject: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "cylinder.split.1x2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Text("Mock Data")
                    .font(.r(.headline, .semibold))
                Spacer()
                Text(isInjected ? "Active" : "Inactive")
                    .font(.r(.caption2, .semibold))
                    .foregroundStyle(isInjected ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isInjected ? Color.green : Color.secondary).opacity(0.15))
                    )
            }

            Text("Inject 30 days of realistic food logs, wellness data, stress readings, and HealthKit metrics across all screens.")
                .font(.r(.caption, .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    onInject()
                } label: {
                    Label("Inject Data", systemImage: "plus.circle.fill")
                        .font(.r(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brand)
                .disabled(isInjected)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash.fill")
                        .font(.r(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!isInjected)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .appShadow(radius: 15, y: 5)
        )
        .confirmationDialog(
            "Clear all mock data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Mock Data", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will remove all injected food logs, wellness logs, and stress readings. Your real data is not affected.")
        }
    }
}
#endif
