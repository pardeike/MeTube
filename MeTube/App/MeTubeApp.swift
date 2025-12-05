//
//  MeTubeApp.swift
//  MeTube
//
//  A distraction-free YouTube subscription feed app
//

import SwiftUI
import BackgroundTasks

@main
struct MeTubeApp: App {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var feedViewModel = FeedViewModel()
    
    init() {
        // Register background refresh task
        FeedViewModel.registerBackgroundTask()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(feedViewModel)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule background refresh when app enters background
                    feedViewModel.scheduleBackgroundRefresh()
                }
        }
        .backgroundTask(.appRefresh(FeedConfig.backgroundTaskIdentifier)) {
            // Handle background refresh
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
