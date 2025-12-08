//
//  HubSyncManager.swift
//  MeTube
//
//  Manager for synchronizing video feed from the MeTube Hub Server
//  Implements incremental sync with delta loading
//

import Foundation
import SwiftData

/// Configuration for hub sync operations
enum HubSyncConfig {
    /// Minimum interval between syncs (in seconds)
    static let minimumSyncInterval: TimeInterval = 60 * 60 // 1 hour
    
    /// Number of videos to fetch per page
    static let pageLimit = 200
    
    /// Maximum number of retry attempts
    static let maxRetries = 3
    
    /// Base delay for exponential backoff (in seconds)
    static let baseRetryDelay: TimeInterval = 1.0
    
    /// UserDefaults key for last feed sync timestamp
    static let lastFeedSyncKey = "lastFeedSync"
}

/// Manager for syncing video feed from the hub server
@MainActor
class HubSyncManager {
    private let videoRepository: VideoRepository
    private let channelRepository: ChannelRepository
    private let hubServerService: HubServerService
    private let youtubeService: YouTubeService
    private let userId: String
    
    /// Last time the feed was synced
    private var lastFeedSync: Date? {
        get {
            UserDefaults.standard.object(forKey: HubSyncConfig.lastFeedSyncKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: HubSyncConfig.lastFeedSyncKey)
        }
    }
    
    init(
        videoRepository: VideoRepository,
        channelRepository: ChannelRepository,
        hubServerService: HubServerService = HubServerService(),
        youtubeService: YouTubeService = YouTubeService(),
        userId: String
    ) {
        self.videoRepository = videoRepository
        self.channelRepository = channelRepository
        self.hubServerService = hubServerService
        self.youtubeService = youtubeService
        self.userId = userId
    }
    
    // MARK: - Sync Operations
    
    /// Check if sync is needed based on last sync time
    func shouldSync() -> Bool {
        guard let lastSync = lastFeedSync else {
            appLog("No previous sync found, sync needed", category: .feed, level: .info)
            return true
        }
        
        let elapsed = Date().timeIntervalSince(lastSync)
        let shouldSync = elapsed >= HubSyncConfig.minimumSyncInterval
        
        if shouldSync {
            appLog("Last sync was \(Int(elapsed))s ago, sync needed", category: .feed, level: .info)
        } else {
            appLog("Last sync was \(Int(elapsed))s ago, sync not needed yet", category: .feed, level: .debug)
        }
        
        return shouldSync
    }
    
    /// Perform sync if needed (non-blocking check)
    func syncIfNeeded() async throws {
        guard shouldSync() else {
            appLog("Sync not needed at this time", category: .feed, level: .debug)
            return
        }
        
        try await performSync()
    }
    
    /// Perform a full sync operation
    /// - Parameter accessToken: OAuth token for YouTube API (needed for channel registration)
    /// - Returns: Number of new videos added
    @discardableResult
    func performSync(accessToken: String? = nil) async throws -> Int {
        appLog("Starting hub sync", category: .feed, level: .info)
        
        // 1. Check hub server health
        appLog("Checking hub server health", category: .feed, level: .debug)
        let health = try await hubServerService.checkHealth()
        appLog("Hub server healthy - \(health.stats.channels) channels, \(health.stats.videos) videos", category: .feed, level: .success)
        
        // 2. Register channels if we have an access token and no channels yet
        let channelCount = try channelRepository.count()
        if channelCount == 0, let token = accessToken {
            try await registerChannels(accessToken: token)
        }
        
        // 3. Perform incremental or full feed fetch
        let newVideosCount = try await fetchFeed()
        
        // 4. Update last sync timestamp
        lastFeedSync = Date()
        appLog("Hub sync completed - added \(newVideosCount) new videos", category: .feed, level: .success)
        
        return newVideosCount
    }
    
    // MARK: - Channel Registration
    
    /// Register user's channels with the hub server
    private func registerChannels(accessToken: String) async throws {
        appLog("Fetching subscriptions from YouTube", category: .feed, level: .info)
        
        // Fetch channels from YouTube
        let channels = try await youtubeService.fetchSubscriptions(accessToken: accessToken)
        appLog("Fetched \(channels.count) channels from YouTube", category: .feed, level: .success)
        
        // Convert to ChannelEntity and save to local database
        let channelEntities = channels.map { channel in
            ChannelEntity(
                channelId: channel.id,
                name: channel.name,
                thumbnailURL: channel.thumbnailURL?.absoluteString,
                channelDescription: channel.description,
                uploadsPlaylistId: channel.uploadsPlaylistId
            )
        }
        try channelRepository.saveChannels(channelEntities)
        appLog("Saved \(channelEntities.count) channels to local database", category: .feed, level: .success)
        
        // Register with hub server
        appLog("Registering channels with hub server", category: .feed, level: .info)
        let channelIds = channels.map { $0.id }
        try await hubServerService.registerChannels(userId: userId, channelIds: channelIds)
        appLog("Registered \(channelIds.count) channels with hub server", category: .feed, level: .success)
    }
    
    // MARK: - Feed Fetch
    
    /// Fetch feed from hub server (incremental or full)
    private func fetchFeed() async throws -> Int {
        // Determine if we should use incremental sync
        let since = lastFeedSync
        
        if let since = since {
            appLog("Fetching incremental feed since \(since)", category: .feed, level: .info)
        } else {
            appLog("Fetching full feed (first sync)", category: .feed, level: .info)
        }
        
        // Fetch with pagination
        var allVideos: [VideoDTO] = []
        var cursor: String? = nil
        var pageCount = 0
        
        repeat {
            pageCount += 1
            appLog("Fetching feed page \(pageCount)", category: .feed, level: .debug)
            
            let response = try await fetchFeedPage(since: since, cursor: cursor)
            allVideos.append(contentsOf: response.videos)
            cursor = response.nextCursor
            
            appLog("Fetched \(response.videos.count) videos in page \(pageCount)", category: .feed, level: .debug)
            
            // Prevent infinite loops
            if pageCount > 100 {
                appLog("Too many pages, stopping pagination", category: .feed, level: .warning)
                break
            }
        } while cursor != nil
        
        appLog("Fetched total of \(allVideos.count) videos from hub server", category: .feed, level: .success)
        
        // Merge videos into local database
        let newCount = try await mergeFeed(videos: allVideos)
        
        return newCount
    }
    
    /// Fetch a single page of feed
    private func fetchFeedPage(since: Date?, cursor: String?) async throws -> FeedResponse {
        // Use retry logic with exponential backoff
        var lastError: Error?
        
        for attempt in 0..<HubSyncConfig.maxRetries {
            do {
                let response = try await hubServerService.fetchFeed(
                    userId: userId,
                    since: since,
                    cursor: cursor,
                    limit: HubSyncConfig.pageLimit
                )
                return response
            } catch let error as HubError where error == .userNotFound {
                // User not found - need to re-register channels
                appLog("User not found on hub server, re-registration needed", category: .feed, level: .warning)
                throw error
            } catch {
                lastError = error
                
                if attempt < HubSyncConfig.maxRetries - 1 {
                    let delay = HubSyncConfig.baseRetryDelay * pow(2.0, Double(attempt))
                    appLog("Feed fetch failed (attempt \(attempt + 1)), retrying in \(delay)s", category: .feed, level: .warning)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        appLog("Feed fetch failed after \(HubSyncConfig.maxRetries) attempts", category: .feed, level: .error)
        throw lastError ?? HubError.fetchFailed
    }
    
    /// Merge fetched videos into local database
    private func mergeFeed(videos: [VideoDTO]) async throws -> Int {
        appLog("Merging \(videos.count) videos into local database", category: .feed, level: .info)
        
        // Convert VideoDTO to VideoEntity
        var videoEntities: [VideoEntity] = []
        
        for videoDTO in videos {
            // Skip videos without required fields
            guard let title = videoDTO.title,
                  let duration = videoDTO.duration,
                  duration >= 60 // Filter out shorts (< 60 seconds)
            else {
                continue
            }
            
            let entity = VideoEntity(
                videoId: videoDTO.videoId,
                channelId: videoDTO.channelId,
                title: title,
                videoDescription: videoDTO.description,
                thumbnailURL: videoDTO.thumbnailUrl,
                duration: duration,
                publishedAt: videoDTO.publishedAt
            )
            videoEntities.append(entity)
        }
        
        // Merge into repository (deduplicates by videoId)
        let newCount = try videoRepository.mergeVideos(videoEntities)
        
        appLog("Merged \(videoEntities.count) videos, \(newCount) new", category: .feed, level: .success)
        return newCount
    }
    
    // MARK: - Force Sync
    
    /// Force a sync even if the interval hasn't elapsed
    func forceSync(accessToken: String? = nil) async throws -> Int {
        appLog("Forcing hub sync", category: .feed, level: .info)
        return try await performSync(accessToken: accessToken)
    }
    
    /// Reset sync state (for testing or troubleshooting)
    func resetSyncState() {
        lastFeedSync = nil
        appLog("Reset hub sync state", category: .feed, level: .info)
    }
}
