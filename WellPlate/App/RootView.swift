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
            }
        }
        .onOpenURL { url in
            pendingDeepLink = url
        }
    }
}

#Preview {
    RootView()
}
