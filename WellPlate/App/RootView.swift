//
//  RootView.swift
//  WellPlate
//
//  Created by Hari's Mac on 16.02.2026.
//  Updated by Claude on 20.02.2026.
//

import SwiftUI

struct RootView: View {
    @State private var showSplash = false
    @State private var showOnboarding = !UserProfileManager.shared.hasCompletedOnboarding
    @State private var pendingDeepLink: URL? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var promptCoordinator: DailyPromptCoordinator

    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                showSplash = false
                            }
                        }
                    }
            } else if showOnboarding {
                OnboardingView {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        showOnboarding = false
                    }
                }
                .transition(.opacity)
            } else {
                MainTabView(pendingDeepLink: $pendingDeepLink)
                    .transition(.opacity)
                    .sheet(item: $promptCoordinator.pendingPrompt) { kind in
                        QuickCheckInSheet(kind: kind, coordinator: promptCoordinator)
                    }
            }
        }
        .onOpenURL { url in
            pendingDeepLink = url
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                StressTimerService.shared.start()
                guard !showSplash, !showOnboarding else { return }
                Task {
                    await promptCoordinator.evaluateOnAppForeground(
                        now: Date(),
                        modelContext: modelContext,
                        healthService: HealthKitServiceFactory.shared
                    )
                }
            case .background, .inactive:
                StressTimerService.shared.stop()
            @unknown default:
                break
            }
        }
    }
}

#Preview {
    RootView()
}
