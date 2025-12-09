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
            
            // Configure the model container
            // Allow automatic migration and schema evolution
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContainer = container
            
            // Create FeedViewModel with model context
            let context = ModelContext(container)
            let viewModel = FeedViewModel(modelContext: context)
            _feedViewModel = StateObject(wrappedValue: viewModel)
            
            appLog("SwiftData ModelContainer initialized successfully", category: .feed, level: .success)
        } catch {
            // If the store fails to load, it might be due to schema changes
            // Log the error and attempt to recover
            appLog("Failed to initialize ModelContainer: \(error)", category: .feed, level: .error)
            
            // Attempt recovery by deleting the old store and creating a new one
            do {
                let schema = Schema([
                    VideoEntity.self,
                    ChannelEntity.self,
                    StatusEntity.self
                ])
                
                // Get the default store URL
                let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
                
                // Try to remove the old store files if they exist
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: storeURL.path) {
                    try? fileManager.removeItem(at: storeURL)
                    appLog("Removed incompatible store at: \(storeURL.path)", category: .feed, level: .warning)
                }
                
                // Also try to remove associated files
                let shmURL = storeURL.appendingPathExtension("shm")
                let walURL = storeURL.appendingPathExtension("wal")
                try? fileManager.removeItem(at: shmURL)
                try? fileManager.removeItem(at: walURL)
                
                // Try again with a fresh configuration
                let modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    allowsSave: true
                )
                
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                self.modelContainer = container
                
                let context = ModelContext(container)
                let viewModel = FeedViewModel(modelContext: context)
                _feedViewModel = StateObject(wrappedValue: viewModel)
                
                appLog("SwiftData ModelContainer initialized successfully after store reset", category: .feed, level: .success)
            } catch {
                // If recovery fails, this is fatal
                fatalError("Failed to initialize ModelContainer even after attempted recovery: \(error)")
            }
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
                // Trigger reconciliation and sync when app becomes active
                Task {
                    // First, reconcile to check for new videos (respects 15-minute rate limit)
                    await feedViewModel.reconcileOnForeground()
                    // Then, perform regular sync if needed
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
