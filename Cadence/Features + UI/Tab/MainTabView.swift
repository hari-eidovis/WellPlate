//
//  MainTabView.swift
//  Cadence
//
//  Created by Hari's Mac on 20.02.2026.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var tabSelector: TabSelector
    @EnvironmentObject private var promptCoordinator: DailyPromptCoordinator
    @Binding var pendingDeepLink: URL?

    /// Shared across Home (live score readout) and Stress (full UI).
    @StateObject private var stressViewModel: StressViewModel

    init(pendingDeepLink: Binding<URL?>, modelContext: ModelContext) {
        self._pendingDeepLink = pendingDeepLink
        let snapshot: StressMockSnapshot? = {
            #if DEBUG
            return AppConfig.shared.mockMode ? StressMockSnapshot.default : nil
            #else
            return nil
            #endif
        }()
        _stressViewModel = StateObject(
            wrappedValue: StressViewModel(modelContext: modelContext, mockSnapshot: snapshot)
        )
    }

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
                HomeView(selectedTab: homeIndexBinding, stressViewModel: stressViewModel)
            } label: {
                Label("Home", systemImage: "house.fill")
            }

            // MARK: - Stress
            Tab(value: TabKind.stress) {
                StressView(viewModel: stressViewModel)
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
            guard let url, url.scheme == "cadence" else { return }
            switch url.host {
            case "stress": tabSelector.selectedTab = .stress
            default: break
            }
            pendingDeepLink = nil
        }
        .task {
            // Bind manual-input updates here so the shared VM responds to
            // mood/water/food saves regardless of which tab is active.
            // HK auth + initial loadData stay in StressView.task to preserve
            // the existing UX where the auth prompt is tied to the Stress tab.
            stressViewModel.bindManualInputUpdates(from: promptCoordinator)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: StressReading.self, WellnessDayLog.self, FoodLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return MainTabView(
        pendingDeepLink: .constant(nil as URL?),
        modelContext: container.mainContext
    )
    .environmentObject(TabSelector())
    .environmentObject(DailyPromptCoordinator())
    .modelContainer(container)
}
