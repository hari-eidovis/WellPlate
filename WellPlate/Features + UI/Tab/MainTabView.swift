//
//  MainTabView.swift
//  WellPlate
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tabSelector: TabSelector
    @Binding var pendingDeepLink: URL?

    /// Bridges `tabSelector.selectedTab` (TabKind) to legacy `Binding<Int>`
    /// consumers (currently `HomeView`).
    private var homeIndexBinding: Binding<Int> {
        Binding<Int>(
            get: { tabSelector.selectedTab.legacyIndex },
            set: { tabSelector.selectedTab = TabKind.fromLegacyIndex($0) }
        )
    }

    var body: some View {
        TabView(selection: $tabSelector.selectedTab) {
            // MARK: - Home
            Tab(value: TabKind.home) {
                HomeView(selectedTab: homeIndexBinding)
            } label: {
                Label("Home", systemImage: "house.fill")
            }

            // MARK: - Stress
            Tab(value: TabKind.stress) {
                StressView(viewModel: {
                    #if DEBUG
                    if AppConfig.shared.mockMode {
                        let snap = StressMockSnapshot.default
                        return StressViewModel(
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
            Tab(value: TabKind.history) {
                HistoryView()
            } label: {
                Label("History", systemImage: "calendar.badge.clock")
            }

            // MARK: - Profile
            Tab(value: TabKind.profile) {
                ProfilePlaceholderView()
            } label: {
                Label("Profile", systemImage: "person.crop.circle.fill")
            }
        }
        .tint(tabSelector.selectedTab == .stress ? Color(hex: "5E9FFF") : AppColors.brand)
        .sensoryFeedback(.selection, trigger: tabSelector.selectedTab)
        .sheet(item: $tabSelector.presentedSheet) { kind in
            switch kind {
            case .water:
                let goals = UserGoals.current(in: modelContext)
                NavigationStack {
                    WaterDetailView(totalGlasses: goals.waterDailyCups, cupSizeML: goals.waterCupSizeML)
                }
            case .foodLog:
                // Full meal-log sheet requires HomeViewModel; for now, a
                // tab-switch-only behaviour. HomeView's meal log button is
                // visible once the user lands on Home.
                Color.clear.onAppear { tabSelector.presentedSheet = nil }
            }
        }
        .onChange(of: pendingDeepLink) { _, url in
            guard let url, url.scheme == "wellplate" else { return }
            switch url.host {
            case "stress": tabSelector.selectedTab = .stress
            default: break
            }
            pendingDeepLink = nil
        }
    }
}

#Preview {
    MainTabView(pendingDeepLink: .constant(nil))
        .environmentObject(TabSelector())
}
