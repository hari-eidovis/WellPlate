import SwiftUI

struct PlaygroundRootView: View {
    @StateObject private var store = PlaygroundStore()

    var body: some View {
        TabView {
            IntakePlaygroundView()
                .tabItem {
                    Label("Intake", systemImage: "fork.knife")
                }

            WellnessPlaygroundView()
                .tabItem {
                    Label("Wellness", systemImage: "heart.text.square")
                }

            AboutPlaygroundView()
                .tabItem {
                    Label("Challenge", systemImage: "checkmark.shield")
                }
        }
        .environmentObject(store)
        .tint(.orange)
    }
}

#Preview {
    PlaygroundRootView()
}
