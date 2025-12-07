//
//  FeedViewModel.swift
//  MeTube
//
//  ViewModel for the subscription feed
//

import Foundation
import Combine
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

/// ViewModel for managing the subscription feed
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
    
    /// Convenience property for backward compatibility
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
    
    // MARK: - Services
    
    private let youtubeService = YouTubeService()
    private let cloudKitService = CloudKitService()
    private let hubServerService = HubServerService()
    private let hubUserId = HubServerService.getUserId()
    
    // MARK: - Cache
    
    private var videoStatusCache: [String: VideoStatus] = [:]
    private var existingVideoIds: Set<String> = []
    
    /// Cached app settings loaded from CloudKit
    private var appSettings: AppSettings = .default
    
    // MARK: - Task Management
    
    /// Task for loading cached data from CloudKit
    private var loadCacheTask: Task<Void, Never>?
    /// Task for saving cached data to CloudKit
    private var saveCacheTask: Task<Void, Never>?
    /// Task for loading video statuses in background
    private var loadStatusTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        appLog("FeedViewModel initializing", category: .feed, level: .info)
        // Prepare schema and load all data from CloudKit asynchronously
        loadCachedData()
        appLog("FeedViewModel initialized - preparing schema and loading data from CloudKit", category: .feed, level: .success)
    }
    
    // MARK: - CloudKit Persistence
    
    /// Loads cached channels, videos, and app settings from CloudKit
    /// This syncs data across devices and avoids the ~4MB UserDefaults size limit
    private func loadCachedData() {
        // Cancel any existing load task
        loadCacheTask?.cancel()
        
        // CloudKit operations are async, so we need to start a Task
        // Store the task reference to allow cancellation if needed
        loadCacheTask = Task {
            // Prepare schema first to check for any configuration issues
            await prepareCloudKitSchema()
            // Then load cached data
            await loadCachedDataFromCloudKit()
        }
    }
    
    /// Prepares the CloudKit schema and logs any configuration issues
    private func prepareCloudKitSchema() async {
        let result = await cloudKitService.prepareSchema()
        
        if !result.allReady {
            // Log detailed errors for troubleshooting
            for error in result.errors {
                appLog("CloudKit schema issue: \(error)", category: .cloudKit, level: .warning)
            }
            appLog("CloudKit schema needs configuration. Open CloudKit Dashboard at https://icloud.developer.apple.com and configure indexes. See CONFIG.md section 'CloudKit Setup' > 'Step 3: Configure Field Indexes' for details.", category: .cloudKit, level: .warning)
        }
    }
    
    /// Async method to load cached data from CloudKit
    /// Each data type is loaded independently to support partial database setups
    private func loadCachedDataFromCloudKit() async {
        appLog("Loading cached data from CloudKit", category: .cloudKit, level: .debug)
        
        // Load app settings from CloudKit first (fetched by ID, not queried)
        do {
            if let settings = try await cloudKitService.fetchAppSettings() {
                appSettings = settings
                lastRefreshDate = settings.lastRefreshDate
                quotaInfo = QuotaInfo(
                    usedToday: settings.quotaUsedToday,
                    resetDate: settings.quotaResetDate ?? Date()
                )
                
                // Check if quota should be reset (new day in Pacific Time)
                if let resetDate = settings.quotaResetDate, shouldResetQuota(lastResetDate: resetDate) {
                    quotaInfo = QuotaInfo(usedToday: 0, resetDate: nextQuotaResetDate())
                }
                
                appLog("Loaded app settings from CloudKit", category: .cloudKit, level: .success)
            }
        } catch {
            appLog("Failed to load app settings from CloudKit: \(error)", category: .cloudKit, level: .error)
        }
        
        // Load cached channels from CloudKit (requires 'name' index)
        do {
            let cachedChannels = try await cloudKitService.fetchAllChannels()
            if !cachedChannels.isEmpty {
                channels = cachedChannels.sorted { $0.name.lowercased() < $1.name.lowercased() }
                appLog("Loaded \(channels.count) cached channels from CloudKit", category: .cloudKit, level: .success)
            } else {
                appLog("No cached channels found in CloudKit", category: .cloudKit, level: .info)
            }
        } catch {
            appLog("Failed to load cached channels from CloudKit: \(error)", category: .cloudKit, level: .error)
        }
        
        // Load cached videos from CloudKit (requires 'status' index)
        do {
            let cachedVideos = try await cloudKitService.fetchAllVideos()
            if !cachedVideos.isEmpty {
                allVideos = cachedVideos
                appLog("Loaded \(allVideos.count) cached videos from CloudKit", category: .cloudKit, level: .success)
                
                // Load video statuses in the background without blocking the UI
                // This allows users to see and interact with videos immediately
                // Cancel any existing status load task
                loadStatusTask?.cancel()
                loadStatusTask = Task {
                    await loadVideoStatusesInBackground()
                }
            } else {
                appLog("No cached videos found in CloudKit", category: .cloudKit, level: .info)
            }
        } catch {
            appLog("Failed to load cached videos from CloudKit: \(error)", category: .cloudKit, level: .error)
        }
    }
    
    /// Saves channels and videos to CloudKit for persistence and cross-device sync
    private func saveCachedData() {
        // Cancel any existing save task to avoid redundant saves
        saveCacheTask?.cancel()
        
        // Store the task reference to prevent concurrent saves
        saveCacheTask = Task {
            await saveCachedDataToCloudKit()
        }
    }
    
    /// Async method to save cached data to CloudKit
    /// Each data type is saved independently to support partial database setups
    private func saveCachedDataToCloudKit() async {
        appLog("Saving data to CloudKit", category: .cloudKit, level: .debug, context: [
            "channels": channels.count,
            "videos": allVideos.count
        ])
        
        // Save app settings to CloudKit (saved by ID, doesn't require indexes)
        do {
            appSettings.lastRefreshDate = lastRefreshDate
            appSettings.quotaUsedToday = quotaInfo.usedToday
            appSettings.quotaResetDate = quotaInfo.resetDate
            try await cloudKitService.saveAppSettings(appSettings)
            appLog("Saved app settings to CloudKit", category: .cloudKit, level: .success)
        } catch {
            appLog("Failed to save app settings to CloudKit: \(error)", category: .cloudKit, level: .error)
        }
        
        // Save channels to CloudKit
        if !channels.isEmpty {
            do {
                try await cloudKitService.batchSaveChannels(channels)
                appLog("Saved \(channels.count) channels to CloudKit", category: .cloudKit, level: .success)
            } catch {
                appLog("Failed to save channels to CloudKit: \(error)", category: .cloudKit, level: .error)
            }
        }
        
        // Save videos to CloudKit
        if !allVideos.isEmpty {
            do {
                try await cloudKitService.batchSaveVideos(allVideos)
                appLog("Saved \(allVideos.count) videos to CloudKit", category: .cloudKit, level: .success)
            } catch {
                appLog("Failed to save videos to CloudKit: \(error)", category: .cloudKit, level: .error)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Converts a VideoDTO from the hub server to a Video model
    /// Returns nil if the video should be filtered (e.g., Shorts, missing channel)
    private func convertVideoDTO(_ dto: VideoDTO) -> Video? {
        // Find the channel for this video
        guard let channel = channels.first(where: { $0.id == dto.channelId }) else {
            return nil
        }
        
        // Skip shorts (videos under threshold duration)
        if let duration = dto.duration, duration < FeedConfig.shortsDurationThreshold {
            return nil
        }
        
        return Video(
            id: dto.videoId,
            title: dto.title ?? "Untitled",
            channelId: dto.channelId,
            channelName: channel.name,
            publishedDate: dto.publishedAt,
            duration: dto.duration ?? 0,
            thumbnailURL: dto.thumbnailUrl.flatMap { URL(string: $0) },
            description: dto.description,
            status: videoStatusCache[dto.videoId] ?? .unwatched
        )
    }
    
    // MARK: - Public Methods
    
    /// Performs a full refresh of the feed using the MeTube Hub Server
    /// This reduces API quota usage by fetching from the server instead of YouTube directly
    /// Use this on first launch or when user explicitly requests full refresh
    func fullRefresh(accessToken: String) async {
        appLog("Starting full refresh via hub server", category: .feed, level: .info)
        
        loadingState = .loadingSubscriptions(progress: "")
        error = nil
        newVideosCount = 0
        
        do {
            // 1. Check hub server health
            appLog("Checking hub server health", category: .feed, level: .info)
            loadingState = .loadingSubscriptions(progress: "Connecting to server...")
            let health = try await hubServerService.checkHealth()
            appLog("Hub server healthy - \(health.stats.channels) channels, \(health.stats.videos) videos", category: .feed, level: .success)
            
            // 2. Fetch user's subscribed channels from YouTube (still need OAuth for this)
            appLog("Fetching subscriptions from YouTube", category: .youtube, level: .info)
            loadingState = .loadingSubscriptions(progress: "Fetching your channels...")
            let fetchedChannels = try await youtubeService.fetchSubscriptions(accessToken: accessToken)
            channels = fetchedChannels.sorted { $0.name.lowercased() < $1.name.lowercased() }
            appLog("Fetched \(channels.count) channels from YouTube", category: .youtube, level: .success)
            
            // Small quota usage for fetching subscriptions only (no video fetching)
            let subscriptionQuota = (channels.count / 50) + 1 + (channels.count / 50) + 1
            addQuotaUsage(subscriptionQuota)
            
            // 3. Register channels with hub server
            appLog("Registering channels with hub server", category: .feed, level: .info)
            loadingState = .loadingSubscriptions(progress: "Registering channels with server...")
            let channelIds = channels.map { $0.id }
            try await hubServerService.registerChannels(userId: hubUserId, channelIds: channelIds)
            appLog("Registered \(channelIds.count) channels with hub server", category: .feed, level: .success)
            
            // 4. Load existing video statuses from CloudKit if not already cached
            // Only show loading state if we have no cached statuses and no cached videos
            if videoStatusCache.isEmpty {
                // Only block UI if we have no existing videos to show
                if allVideos.isEmpty {
                    appLog("Loading video statuses from CloudKit (blocking)", category: .cloudKit, level: .info)
                    loadingState = .loadingStatuses
                    videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
                    appLog("Loaded \(videoStatusCache.count) video statuses from CloudKit", category: .cloudKit, level: .success)
                } else {
                    // Load statuses in background without blocking UI since we have videos to show
                    appLog("Loading video statuses from CloudKit (background)", category: .cloudKit, level: .info)
                    // Cancel any existing status load task
                    loadStatusTask?.cancel()
                    loadStatusTask = Task {
                        do {
                            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
                            appLog("Loaded \(videoStatusCache.count) video statuses from CloudKit in background", category: .cloudKit, level: .success)
                        } catch {
                            appLog("Error loading video statuses in background: \(error)", category: .cloudKit, level: .error)
                        }
                    }
                }
            } else {
                appLog("Using cached video statuses (\(videoStatusCache.count))", category: .cloudKit, level: .info)
            }
            
            // Store existing video IDs for comparison
            existingVideoIds = Set(allVideos.map { $0.id })
            
            // 5. Fetch videos from hub server (no individual API calls!)
            appLog("Fetching videos from hub server", category: .feed, level: .info)
            loadingState = .loadingVideos(channelIndex: 1, totalChannels: 1, channelName: "Loading from server...")
            let feedResponse = try await hubServerService.fetchFeed(userId: hubUserId, limit: 200)
            appLog("Fetched \(feedResponse.videos.count) videos from hub server", category: .feed, level: .success)
            
            // 6. Convert VideoDTO to Video model with channel info
            var newVideos: [Video] = []
            var newCount = 0
            
            for videoDTO in feedResponse.videos {
                guard let video = convertVideoDTO(videoDTO) else {
                    continue
                }
                
                if !existingVideoIds.contains(video.id) {
                    newCount += 1
                }
                
                newVideos.append(video)
            }
            
            allVideos = newVideos
            newVideosCount = newCount
            loadingState = .idle
            
            // Save refresh timestamp and cached data
            lastRefreshDate = Date()
            appSettings.lastFullRefreshDate = Date()
            saveCachedData()
            
            appLog("Full refresh completed via hub server", category: .feed, level: .success, context: [
                "totalVideos": allVideos.count,
                "newVideos": newCount,
                "channels": channels.count
            ])
            
        } catch let hubError as HubError {
            appLog("Hub server error during full refresh: \(hubError)", category: .feed, level: .error)
            self.error = hubError.errorDescription
            loadingState = .idle
        } catch let apiError as YouTubeAPIError {
            appLog("YouTube API error during full refresh: \(apiError)", category: .youtube, level: .error)
            handleAPIError(apiError)
            loadingState = .idle
        } catch {
            appLog("Error during full refresh: \(error)", category: .feed, level: .error)
            self.error = error.localizedDescription
            loadingState = .idle
        }
    }
    
    /// Performs an incremental refresh - fetches only recent videos from hub server
    /// More efficient than full refresh as it uses the 'since' parameter
    func incrementalRefresh(accessToken: String) async {
        appLog("Starting incremental refresh via hub server", category: .feed, level: .info, context: [
            "cachedChannels": channels.count,
            "cachedVideos": allVideos.count
        ])
        
        // If we have no data, do a full refresh
        guard !channels.isEmpty else {
            appLog("No cached channels - falling back to full refresh", category: .feed, level: .info)
            await fullRefresh(accessToken: accessToken)
            return
        }
        
        // Check if we need a full refresh (once per day)
        if shouldDoFullRefresh() {
            appLog("Full refresh interval exceeded - doing full refresh", category: .feed, level: .info)
            await fullRefresh(accessToken: accessToken)
            return
        }
        
        appLog("Proceeding with incremental refresh via hub server", category: .feed, level: .info)
        loadingState = .refreshing
        error = nil
        newVideosCount = 0
        
        do {
            // Store existing video IDs for comparison
            existingVideoIds = Set(allVideos.map { $0.id })
            appLog("Existing video IDs count: \(existingVideoIds.count)", category: .feed, level: .debug)
            
            // Fetch only recent videos from hub server using 'since' parameter
            let sinceDate = lastRefreshDate ?? Date.distantPast
            appLog("Fetching videos since \(sinceDate)", category: .feed, level: .info)
            let feedResponse = try await hubServerService.fetchFeed(
                userId: hubUserId,
                since: sinceDate,
                limit: 100
            )
            appLog("Fetched \(feedResponse.videos.count) videos from hub server", category: .feed, level: .success)
            
            // Load video statuses only if not cached
            if videoStatusCache.isEmpty {
                appLog("Loading video statuses from CloudKit", category: .cloudKit, level: .info)
                videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
                appLog("Loaded \(videoStatusCache.count) video statuses", category: .cloudKit, level: .success)
            } else {
                appLog("Using cached video statuses (\(videoStatusCache.count))", category: .cloudKit, level: .info)
            }
            
            // Convert VideoDTO to Video model and merge with existing
            var videoDict: [String: Video] = [:]
            for video in allVideos {
                videoDict[video.id] = video
            }
            
            var newCount = 0
            for videoDTO in feedResponse.videos {
                guard let video = convertVideoDTO(videoDTO) else {
                    continue
                }
                
                if videoDict[video.id] == nil {
                    newCount += 1
                }
                videoDict[video.id] = video
            }
            
            allVideos = Array(videoDict.values)
            newVideosCount = newCount
            loadingState = .idle
            
            // Save refresh timestamp and cached data
            lastRefreshDate = Date()
            saveCachedData()
            
            appLog("Incremental refresh completed via hub server", category: .feed, level: .success, context: [
                "totalVideos": allVideos.count,
                "newVideos": newCount
            ])
            
        } catch let hubError as HubError {
            appLog("Hub server error during incremental refresh: \(hubError)", category: .feed, level: .error)
            self.error = hubError.errorDescription
            loadingState = .idle
        } catch let apiError as YouTubeAPIError {
            appLog("YouTube API error during incremental refresh: \(apiError)", category: .youtube, level: .error)
            handleAPIError(apiError)
            loadingState = .idle
        } catch {
            appLog("Error during incremental refresh: \(error)", category: .feed, level: .error)
            self.error = error.localizedDescription
            loadingState = .idle
        }
    }
    
    /// Refreshes the feed - uses incremental if data exists, full otherwise
    func refreshFeed(accessToken: String) async {
        appLog("refreshFeed called", category: .feed, level: .info, context: [
            "hasVideos": !allVideos.isEmpty,
            "hasChannels": !channels.isEmpty,
            "videoCount": allVideos.count,
            "channelCount": channels.count
        ])
        
        if allVideos.isEmpty || channels.isEmpty {
            appLog("No cached data - will do full refresh", category: .feed, level: .info)
            await fullRefresh(accessToken: accessToken)
        } else {
            appLog("Cached data exists - will do incremental refresh", category: .feed, level: .info)
            await incrementalRefresh(accessToken: accessToken)
        }
    }
    
    /// Forces a full refresh regardless of existing data
    func forceFullRefresh(accessToken: String) async {
        appLog("Force full refresh requested", category: .feed, level: .info)
        await fullRefresh(accessToken: accessToken)
    }
    
    /// Loads video statuses in the background without blocking the UI
    /// This is called after cached videos are loaded to update their statuses
    private func loadVideoStatusesInBackground() async {
        appLog("Loading video statuses in background", category: .cloudKit, level: .info)
        do {
            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
            appLog("Fetched \(videoStatusCache.count) video statuses from CloudKit", category: .cloudKit, level: .success)
            
            // Apply cached statuses to existing videos
            var updatedCount = 0
            for i in 0..<allVideos.count {
                if let cachedStatus = videoStatusCache[allVideos[i].id] {
                    allVideos[i].status = cachedStatus
                    updatedCount += 1
                }
            }
            appLog("Applied \(updatedCount) status updates to videos", category: .cloudKit, level: .info)
        } catch {
            appLog("Error loading video statuses: \(error)", category: .cloudKit, level: .error)
        }
    }
    
    /// Loads only video statuses from CloudKit (for when videos are already loaded)
    /// This is a public method that can be called when needed (e.g., returning from background)
    func loadVideoStatuses() async {
        // Only load if we don't have statuses cached or if videos exist
        guard !allVideos.isEmpty else {
            appLog("No videos to load statuses for", category: .cloudKit, level: .debug)
            return
        }
        
        // Don't reload if we already have a recent status cache
        guard videoStatusCache.isEmpty else {
            appLog("Video statuses already cached, skipping reload", category: .cloudKit, level: .debug)
            return
        }
        
        await loadVideoStatusesInBackground()
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
    
    /// Updates video status locally and in CloudKit
    private func updateVideoStatus(_ video: Video, newStatus: VideoStatus) async {
        // Find and update the video in our array
        if let index = allVideos.firstIndex(where: { $0.id == video.id }) {
            allVideos[index].status = newStatus
            
            // Update cache
            videoStatusCache[video.id] = newStatus
            
            // Save to CloudKit
            do {
                try await cloudKitService.saveVideoStatus(allVideos[index])
            } catch {
                print("Error saving video status to CloudKit: \(error)")
            }
        }
    }
    
    /// Marks all videos from a channel as watched
    func markChannelAsWatched(_ channelId: String) async {
        let channelVideos = allVideos.filter { $0.channelId == channelId && $0.status == .unwatched }
        
        for video in channelVideos {
            await markAsWatched(video)
        }
    }
    
    /// Clears error message
    func clearError() {
        error = nil
    }
    
    /// Resets the new videos count (call after user has seen the notification)
    func clearNewVideosCount() {
        newVideosCount = 0
    }
    
    // MARK: - Quota Management
    
    private func addQuotaUsage(_ units: Int) {
        quotaInfo.usedToday += units
        // Quota changes will be saved when saveCachedData is called
    }
    
    private func shouldResetQuota(lastResetDate: Date) -> Bool {
        // YouTube quota resets at midnight Pacific Time
        let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar.current
        calendar.timeZone = pacificTimeZone
        
        let lastResetDay = calendar.startOfDay(for: lastResetDate)
        let today = calendar.startOfDay(for: Date())
        
        return today > lastResetDay
    }
    
    private func nextQuotaResetDate() -> Date {
        let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar.current
        calendar.timeZone = pacificTimeZone
        
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.startOfDay(for: tomorrow)
    }
    
    // MARK: - Refresh Timing
    
    private func shouldDoFullRefresh() -> Bool {
        guard let lastFullRefresh = appSettings.lastFullRefreshDate else {
            return true
        }
        return Date().timeIntervalSince(lastFullRefresh) > FeedConfig.fullRefreshInterval
    }
    
    // MARK: - Error Handling
    
    private func handleAPIError(_ apiError: YouTubeAPIError) {
        switch apiError {
        case .quotaExceeded:
            // Mark quota as exceeded
            quotaInfo.usedToday = FeedConfig.dailyQuotaLimit
            error = "YouTube API quota exceeded. The quota resets at midnight Pacific Time. Your existing videos are still available."
        case .unauthorized:
            error = "Authentication expired. Please sign in again."
        case .networkError:
            error = "Network error. Please check your connection and try again."
        default:
            error = apiError.errorDescription
        }
    }
    
    // MARK: - Background Refresh
    
    /// Schedules a background refresh
    nonisolated func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: FeedConfig.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: FeedConfig.backgroundRefreshInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled")
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }
    
    /// Performs a background refresh (called from background task handler)
    /// Uses hub server to fetch only very recent videos
    func performBackgroundRefresh(accessToken: String) async -> Bool {
        appLog("Starting background refresh via hub server", category: .feed, level: .info)
        
        loadingState = .backgroundRefreshing
        
        do {
            // Fetch only very recent videos from hub server
            let sinceDate = Date().addingTimeInterval(-FeedConfig.backgroundRefreshWindow)
            let feedResponse = try await hubServerService.fetchFeed(
                userId: hubUserId,
                since: sinceDate,
                limit: 20
            )
            
            // Merge new videos
            let existingIds = Set(allVideos.map { $0.id })
            var newCount = 0
            
            for videoDTO in feedResponse.videos {
                // Skip if we already have this video
                if existingIds.contains(videoDTO.videoId) {
                    continue
                }
                
                guard let video = convertVideoDTO(videoDTO) else {
                    continue
                }
                
                allVideos.append(video)
                newCount += 1
            }
            
            newVideosCount += newCount
            loadingState = .idle
            lastRefreshDate = Date()
            saveCachedData()
            
            appLog("Background refresh completed - found \(newCount) new videos", category: .feed, level: .success)
            return newCount > 0
            
        } catch {
            appLog("Background refresh failed: \(error)", category: .feed, level: .error)
            loadingState = .idle
            return false
        }
    }
}
