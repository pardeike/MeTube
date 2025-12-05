//
//  MeTubeApp.swift
//  MeTube
//
//  A distraction-free YouTube subscription feed app
//

import SwiftUI

@main
struct MeTubeApp: App {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var feedViewModel = FeedViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(feedViewModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Schedule background refresh when app enters background
                feedViewModel.scheduleBackgroundRefresh()
            case .active:
                // Check if we need to refresh when app becomes active
                Task {
                    await feedViewModel.loadVideoStatuses()
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(FeedConfig.backgroundTaskIdentifier)) {
            await handleBackgroundRefresh()
        }
    }
    
    @Sendable
    private func handleBackgroundRefresh() async {
        // Get access token and perform background refresh
        if let token = await authManager.getAccessToken() {
            let _ = await feedViewModel.performBackgroundRefresh(accessToken: token)
        }
        
        // Schedule next background refresh
        feedViewModel.scheduleBackgroundRefresh()
    }
}
