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

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Intake
            Tab(value: 0) {
                HomeView(viewModel: HomeViewModel(modelContext: modelContext))
            } label: {
                Label("Intake", systemImage: "fork.knife")
            }

            // MARK: - Burn
            Tab(value: 1) {
                BurnView()
            } label: {
                Label("Burn", systemImage: "flame.fill")
            }

            // MARK: - Stress
            Tab(value: 2) {
                StressView(viewModel: StressViewModel(modelContext: modelContext))
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
        .tint(.orange)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

#Preview {
    MainTabView()
}

