import SwiftUI

struct AboutPlaygroundView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Playgrounds Build") {
                    Label("Runs entirely offline with bundled demo logic", systemImage: "wifi.slash")
                    Label("Deterministic resettable state for judging", systemImage: "arrow.counterclockwise")
                    Label("Focused 3-minute demo flow", systemImage: "timer")
                }

                Section("Removed for Submission Safety") {
                    Label("HealthKit authorization and queries", systemImage: "heart.slash")
                    Label("Screen Time APIs (FamilyControls / DeviceActivity)", systemImage: "iphone.slash")
                    Label("Widgets and widget timeline refresh", systemImage: "rectangle.3.group.slash")
                    Label("App extensions and entitlements", systemImage: "puzzlepiece.extension")
                }

                Section("What This Version Demonstrates") {
                    Label("Food logging + macro goal tracking", systemImage: "fork.knife.circle")
                    Label("Stress model from exercise, sleep, diet, and screen time", systemImage: "brain.head.profile")
                    Label("Interactive controls to explain system behavior", systemImage: "slider.horizontal.3")
                }
            }
            .navigationTitle("Challenge Notes")
        }
    }
}

#Preview {
    AboutPlaygroundView()
}
