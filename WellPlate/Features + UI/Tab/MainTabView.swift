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
                    if AppConfig.shared.mockMode || AppConfig.shared.mockDataInjected {
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

            // MARK: - History
            Tab(value: 2) {
                HistoryView()
            } label: {
                Label("History", systemImage: "calendar.badge.clock")
            }

            // MARK: - Profile
            Tab(value: 3) {
                ProfilePlaceholderView()
            } label: {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
        }
       // .tabViewStyle(.sidebarAdaptable)
        .tint(selectedTab == 1 ? Color(hex: "5E9FFF") : AppColors.brand)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: pendingDeepLink) { _, url in
            guard let url, url.scheme == "wellplate" else { return }
            switch url.host {
            case "stress": selectedTab = 1
            default: break
            }
            pendingDeepLink = nil
        }
    }
}

#Preview {
    MainTabView(pendingDeepLink: .constant(nil))
}
