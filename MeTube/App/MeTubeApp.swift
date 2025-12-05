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
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Register background refresh task at app launch
        registerBackgroundTasks()
    }
    
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
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: FeedConfig.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            
            // Handle expiration
            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
            
            Task {
                if let token = await authManager.getAccessToken() {
                    let success = await feedViewModel.performBackgroundRefresh(accessToken: token)
                    refreshTask.setTaskCompleted(success: success)
                } else {
                    refreshTask.setTaskCompleted(success: false)
                }
                
                // Schedule next refresh
                feedViewModel.scheduleBackgroundRefresh()
            }
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
