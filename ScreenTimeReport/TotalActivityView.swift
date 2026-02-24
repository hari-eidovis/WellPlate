//
//  TotalActivityView.swift
//  ScreenTimeReport
//
//  Created on 21.02.2026.
//

import SwiftUI

/// SwiftUI view rendered by the DeviceActivityReport extension.
/// This view runs inside the extension's sandboxed process and displays
/// real screen time data from the system.
struct TotalActivityView: View {
    let report: ActivityReport

    var body: some View {
        Group {
            if report.totalDuration > 0 {
                VStack(spacing: 6) {
                    Text(report.formattedDuration)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    if report.appCount > 0 {
                        Text("\(report.appCount) apps used")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No screen time recorded yet")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
