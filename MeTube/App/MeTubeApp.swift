//
//  MeTubeApp.swift
//  MeTube
//
//  A distraction-free YouTube subscription feed app
//

import SwiftUI
import SwiftData

@main
struct MeTubeApp: App {
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) private var scenePhase
    
    // SwiftData model container for offline-first architecture
    let modelContainer: ModelContainer
    
    // FeedViewModel will be created after ModelContainer is ready
    @StateObject private var feedViewModel: FeedViewModel
    
    init() {
        // Initialize SwiftData model container
        do {
            let schema = Schema([
                VideoEntity.self,
                ChannelEntity.self,
                StatusEntity.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContainer = container
            
            // Create FeedViewModel with model context
            let context = ModelContext(container)
            let viewModel = FeedViewModel(modelContext: context)
            _feedViewModel = StateObject(wrappedValue: viewModel)
            
            appLog("SwiftData ModelContainer initialized successfully", category: .feed, level: .success)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(feedViewModel)
                .modelContainer(modelContainer)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Schedule background refresh when app enters background
                feedViewModel.scheduleBackgroundRefresh()
            case .active:
                // Trigger non-blocking sync when app becomes active
                Task {
                    await feedViewModel.syncIfNeeded()
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
