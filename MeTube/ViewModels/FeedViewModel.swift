//
//  FeedViewModel.swift
//  MeTube
//
//  ViewModel for the subscription feed using offline-first architecture
//

import Foundation
import Combine
import SwiftData
import BackgroundTasks

// MARK: - Feed Configuration

/// Configuration constants for the feed
enum FeedConfig {
    /// Background task identifier
    static let backgroundTaskIdentifier = "com.metube.app.refresh"
    
    /// Minimum interval between background refreshes (in seconds)
    static let backgroundRefreshInterval: TimeInterval = 15 * 60 // 15 minutes
    
    /// Interval for forcing a full refresh (24 hours)
    static let fullRefreshInterval: TimeInterval = 24 * 60 * 60
    
    /// Duration threshold for filtering YouTube Shorts (videos under this duration are excluded)
    static let shortsDurationThreshold: TimeInterval = 60 // seconds
    
    /// Time window for background refresh (fetch videos from last N hours)
    static let backgroundRefreshWindow: TimeInterval = 3600 // 1 hour
    
    /// Daily quota limit (YouTube default is 10,000)
    /// Note: With hub server, we only use quota for fetching user's subscriptions (~2-3 calls)
    static let dailyQuotaLimit = 10000
    
    /// Warning threshold (80% of quota)
    static let quotaWarningThreshold = 8000
}

// MARK: - Loading State

/// Detailed loading state for better UI feedback
enum LoadingState: Equatable {
    case idle
    case loadingSubscriptions(progress: String)
    case loadingVideos(channelIndex: Int, totalChannels: Int, channelName: String)
    case loadingStatuses
    case refreshing
    case backgroundRefreshing
    
    var description: String {
        switch self {
        case .idle:
            return ""
        case .loadingSubscriptions(let progress):
            return "Loading subscriptions... \(progress)"
        case .loadingVideos(let index, let total, let name):
            return "Loading videos (\(index)/\(total)): \(name)"
        case .loadingStatuses:
            return "Syncing watch status..."
        case .refreshing:
            return "Checking for new videos..."
        case .backgroundRefreshing:
            return "Updating in background..."
        }
    }
    
    var isLoading: Bool {
        self != .idle
    }
}

// MARK: - Quota Info

/// Information about API quota usage
struct QuotaInfo {
    var usedToday: Int
    var resetDate: Date
    var isWarning: Bool { usedToday >= FeedConfig.quotaWarningThreshold }
    var isExceeded: Bool { usedToday >= FeedConfig.dailyQuotaLimit }
    var remainingQuota: Int { max(0, FeedConfig.dailyQuotaLimit - usedToday) }
    var percentUsed: Double { Double(usedToday) / Double(FeedConfig.dailyQuotaLimit) * 100 }
}

/// ViewModel for managing the subscription feed with offline-first architecture
@MainActor
class FeedViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var channels: [Channel] = []
    @Published var allVideos: [Video] = []
    @Published var loadingState: LoadingState = .idle
    @Published var error: String?
    @Published var searchText: String = ""
    @Published var selectedStatus: VideoStatus? = .unwatched
    @Published var quotaInfo: QuotaInfo = QuotaInfo(usedToday: 0, resetDate: Date())
    @Published var lastRefreshDate: Date?
    @Published var newVideosCount: Int = 0
    
    var isLoading: Bool { loadingState.isLoading }
    
    // MARK: - Computed Properties
    
    /// Videos filtered by search text and status
    var filteredVideos: [Video] {
        var result = allVideos
        
        // Filter by status
        if let status = selectedStatus {
            result = result.filter { $0.status == status }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { video in
                video.title.lowercased().contains(lowercasedSearch) ||
                video.channelName.lowercased().contains(lowercasedSearch)
            }
        }
        
        // Sort by publish date (newest first)
        return result.sorted { $0.publishedDate > $1.publishedDate }
    }
    
    /// Unwatched videos only
    var unwatchedVideos: [Video] {
        allVideos.filter { $0.status == .unwatched }
            .sorted { $0.publishedDate > $1.publishedDate }
    }
    
    /// Count of unwatched videos per channel
    func unwatchedCount(for channelId: String) -> Int {
        allVideos.filter { $0.channelId == channelId && $0.status == .unwatched }.count
    }
    
    /// Videos for a specific channel
    func videos(for channelId: String) -> [Video] {
        allVideos.filter { $0.channelId == channelId }
            .sorted { $0.publishedDate > $1.publishedDate }
    }
    
    // MARK: - Repositories and Managers
    
    private let videoRepository: VideoRepository
    private let statusRepository: StatusRepository
    private let channelRepository: ChannelRepository
    private let hubSyncManager: HubSyncManager
    private let statusSyncManager: StatusSyncManager
    private let youtubeService = YouTubeService()
    
    // MARK: - Cache
    
    private var channelCache: [String: ChannelEntity] = [:]
    private var statusCache: [String: StatusEntity] = [:]
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        appLog("FeedViewModel initializing with offline-first architecture", category: .feed, level: .info)
        
        // Initialize repositories
        self.videoRepository = VideoRepository(modelContext: modelContext)
        self.statusRepository = StatusRepository(modelContext: modelContext)
        self.channelRepository = ChannelRepository(modelContext: modelContext)
        
        // Initialize sync managers
        let userId = HubServerService.getUserId()
        self.hubSyncManager = HubSyncManager(
            videoRepository: videoRepository,
            channelRepository: channelRepository,
            userId: userId
        )
        self.statusSyncManager = StatusSyncManager(
            statusRepository: statusRepository,
            userId: userId
        )
        
        // Load data from local database
        Task {
            await loadLocalData()
        }
        
        appLog("FeedViewModel initialized successfully", category: .feed, level: .success)
    }
    
    // MARK: - Data Loading
    
    /// Load all data from local database (non-blocking)
    private func loadLocalData() async {
        appLog("Loading data from local database", category: .feed, level: .info)
        
        do {
            // Load channels
            let channelEntities = try channelRepository.fetchAllChannels()
            channels = channelEntities.map { Channel(from: $0) }
            // Handle potential duplicates after removing unique constraints - keep last value
            channelCache = channelEntities.reduce(into: [:]) { $0[$1.channelId] = $1 }
            appLog("Loaded \(channels.count) channels from local database", category: .feed, level: .success)
            
            // Load statuses
            loadingState = .loadingStatuses
            let statusEntities = try statusRepository.fetchAllStatuses()
            // Handle potential duplicates after removing unique constraints - keep last value
            statusCache = statusEntities.reduce(into: [:]) { $0[$1.videoId] = $1 }
            appLog("Loaded \(statusEntities.count) statuses from local database", category: .feed, level: .success)
            
            // Load videos
            let videoEntities = try videoRepository.fetchAllVideos()
            allVideos = videoEntities.map { videoEntity in
                let channel = channelCache[videoEntity.channelId]
                let status = statusCache[videoEntity.videoId]
                return Video(from: videoEntity, channel: channel, status: status)
            }
            appLog("Loaded \(allVideos.count) videos from local database", category: .feed, level: .success)
            
            loadingState = .idle
            
            // Trigger background sync if needed
            await syncIfNeeded()
            
        } catch {
            appLog("Error loading data from local database: \(error)", category: .feed, level: .error)
            self.error = "Failed to load cached data: \(error.localizedDescription)"
            loadingState = .idle
        }
    }
    
    // MARK: - Sync Operations
    
    /// Sync data if needed (non-blocking check)
    func syncIfNeeded() async {
        // Check if hub sync is needed
        if hubSyncManager.shouldSync() {
            appLog("Hub sync needed, starting in background", category: .feed, level: .info)
            Task {
                do {
                    _ = try await hubSyncManager.syncIfNeeded()
                    await refreshFromDatabase()
                } catch {
                    appLog("Background hub sync failed: \(error)", category: .feed, level: .error)
                }
            }
        }
        
        // Check if status sync is needed
        if statusSyncManager.shouldSync() {
            appLog("Status sync needed, starting in background", category: .feed, level: .info)
            Task {
                do {
                    _ = try await statusSyncManager.syncIfNeeded()
                    await refreshFromDatabase()
                } catch {
                    appLog("Background status sync failed: \(error)", category: .feed, level: .error)
                }
            }
        }
    }
    
    // MARK: - Refresh Operations
    
    /// Full refresh from YouTube and hub server
    func fullRefresh(accessToken: String) async {
        appLog("Starting full refresh", category: .feed, level: .info)
        
        loadingState = .refreshing
        error = nil
        newVideosCount = 0
        
        do {
            // Perform sync (includes channel registration and feed fetch)
            let newCount = try await hubSyncManager.performSync(accessToken: accessToken)
            newVideosCount = newCount
            
            // Perform status sync
            _ = try await statusSyncManager.performSync()
            
            // Reload from database
            await refreshFromDatabase()
            
            lastRefreshDate = Date()
            loadingState = .idle
            
            appLog("Full refresh completed - \(newVideosCount) new videos", category: .feed, level: .success)
            
        } catch {
            appLog("Full refresh failed: \(error)", category: .feed, level: .error)
            self.error = error.localizedDescription
            loadingState = .idle
        }
    }
    
    /// Incremental refresh (fetch new videos only)
    func incrementalRefresh(accessToken: String) async {
        appLog("Starting incremental refresh", category: .feed, level: .info)
        
        loadingState = .refreshing
        error = nil
        
        do {
            // Perform incremental sync
            let newCount = try await hubSyncManager.syncIfNeeded()
            newVideosCount = newCount
            
            // Sync statuses
            _ = try await statusSyncManager.syncIfNeeded()
            
            // Reload from database
            await refreshFromDatabase()
            
            lastRefreshDate = Date()
            loadingState = .idle
            
            appLog("Incremental refresh completed - \(newVideosCount) new videos", category: .feed, level: .success)
            
        } catch {
            appLog("Incremental refresh failed: \(error)", category: .feed, level: .error)
            self.error = error.localizedDescription
            loadingState = .idle
        }
    }
    
    /// Refresh feed (decides between full and incremental)
    func refreshFeed(accessToken: String) async {
        // If we have no videos, do a full refresh
        if allVideos.isEmpty {
            await fullRefresh(accessToken: accessToken)
        } else {
            await incrementalRefresh(accessToken: accessToken)
        }
    }
    
    /// Force a full refresh regardless of timing
    func forceFullRefresh(accessToken: String) async {
        await fullRefresh(accessToken: accessToken)
    }
    
    /// Refresh local data from database
    private func refreshFromDatabase() async {
        do {
            // Reload channels
            let channelEntities = try channelRepository.fetchAllChannels()
            channels = channelEntities.map { Channel(from: $0) }
            // Handle potential duplicates after removing unique constraints - keep last value
            channelCache = channelEntities.reduce(into: [:]) { $0[$1.channelId] = $1 }
            
            // Reload statuses
            let statusEntities = try statusRepository.fetchAllStatuses()
            // Handle potential duplicates after removing unique constraints - keep last value
            statusCache = statusEntities.reduce(into: [:]) { $0[$1.videoId] = $1 }
            
            // Reload videos with updated statuses and channels
            let videoEntities = try videoRepository.fetchAllVideos()
            allVideos = videoEntities.map { videoEntity in
                let channel = channelCache[videoEntity.channelId]
                let status = statusCache[videoEntity.videoId]
                return Video(from: videoEntity, channel: channel, status: status)
            }
            
            appLog("Refreshed data from database - \(allVideos.count) videos", category: .feed, level: .success)
        } catch {
            appLog("Error refreshing from database: \(error)", category: .feed, level: .error)
        }
    }
    
    // MARK: - Status Management
    
    /// Load video statuses
    func loadVideoStatuses() async {
        // Statuses are loaded automatically during initialization
        appLog("loadVideoStatuses called", category: .feed, level: .debug)
    }
    
    /// Marks a video as watched
    func markAsWatched(_ video: Video) async {
        appLog("Marking video as watched: \(video.title)", category: .feed, level: .info)
        await updateVideoStatus(video, newStatus: .watched)
    }
    
    /// Marks a video as skipped
    func markAsSkipped(_ video: Video) async {
        appLog("Marking video as skipped: \(video.title)", category: .feed, level: .info)
        await updateVideoStatus(video, newStatus: .skipped)
    }
    
    /// Marks a video as unwatched
    func markAsUnwatched(_ video: Video) async {
        appLog("Marking video as unwatched: \(video.title)", category: .feed, level: .info)
        await updateVideoStatus(video, newStatus: .unwatched)
    }
    
    /// Updates video status locally (will be synced later)
    private func updateVideoStatus(_ video: Video, newStatus: VideoStatus) async {
        do {
            // Update in repository
            try statusRepository.updateStatus(
                forVideoId: video.id,
                status: newStatus.toWatchStatus(),
                synced: false
            )
            
            // Update local cache
            if let index = allVideos.firstIndex(where: { $0.id == video.id }) {
                allVideos[index].status = newStatus
            }
            
            // Trigger background sync
            Task {
                do {
                    _ = try await statusSyncManager.syncIfNeeded()
                } catch {
                    appLog("Background status sync failed: \(error)", category: .cloudKit, level: .error)
                }
            }
            
            appLog("Updated video status locally: \(video.id) -> \(newStatus)", category: .feed, level: .success)
        } catch {
            appLog("Error updating video status: \(error)", category: .feed, level: .error)
            self.error = "Failed to update video status"
        }
    }
    
    /// Marks all videos from a channel as watched
    func markChannelAsWatched(_ channelId: String) async {
        let channelVideos = allVideos.filter { $0.channelId == channelId && $0.status == .unwatched }
        
        for video in channelVideos {
            await markAsWatched(video)
        }
    }
    
    // MARK: - Utility
    
    /// Clears error message
    func clearError() {
        error = nil
    }
    
    /// Resets the new videos count
    func clearNewVideosCount() {
        newVideosCount = 0
    }
    
    // MARK: - Background Operations
    
    /// Perform background refresh
    func performBackgroundRefresh(accessToken: String) async -> Bool {
        appLog("Performing background refresh", category: .feed, level: .info)
        
        do {
            // Perform incremental sync
            let newCount = try await hubSyncManager.syncIfNeeded()
            _ = try await statusSyncManager.syncIfNeeded()
            
            if newCount > 0 {
                await refreshFromDatabase()
                newVideosCount = newCount
                appLog("Background refresh completed - \(newCount) new videos", category: .feed, level: .success)
                return true
            }
            
            return false
        } catch {
            appLog("Background refresh failed: \(error)", category: .feed, level: .error)
            return false
        }
    }
    
    /// Schedule background refresh (called from background context)
    nonisolated func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: FeedConfig.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: FeedConfig.backgroundRefreshInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            appLog("Scheduled background refresh", category: .feed, level: .info)
        } catch {
            appLog("Failed to schedule background refresh: \(error)", category: .feed, level: .error)
        }
    }
}
