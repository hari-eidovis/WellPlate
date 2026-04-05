//
//  MainTabView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @Binding var pendingDeepLink: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Home
            Tab(value: 0) {
                HomeView(selectedTab: $selectedTab)
            } label: {
                Label("Home", systemImage: "house.fill")
            }

            // MARK: - Stress
            Tab(value: 1) {
                StressView(viewModel: {
                    #if DEBUG
                    if AppConfig.shared.mockMode {
                        let snap = StressMockSnapshot.default
                        return StressViewModel(
                            healthService: MockHealthKitService(snapshot: snap),
                            modelContext: modelContext,
                            mockSnapshot: snap
                        )
                    }
                    #endif
                    return StressViewModel(modelContext: modelContext)
                }())
            } label: {
                Label("Stress", systemImage: "brain.head.profile.fill")
            }

            // MARK: - Profile
            Tab(value: 3) {
                ProfilePlaceholderView()
            } label: {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
        }
       // .tabViewStyle(.sidebarAdaptable)
        .tint(AppColors.brand)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: pendingDeepLink) { _, url in
            guard let url, url.scheme == "wellplate" else { return }
            switch url.host {
            case "stress": selectedTab = 2
            default: break
            }
            pendingDeepLink = nil
        }
    }
}

#Preview {
    MainTabView(pendingDeepLink: .constant(nil))
}
