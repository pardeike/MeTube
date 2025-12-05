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
    /// Set to true to disable YouTube API calls for video discovery (uses CloudKit cache only)
    /// This helps avoid hitting API quota limits during testing
    /// NOTE: Only enabled in DEBUG builds
    #if DEBUG
    static let disableVideoAPIFetching = true
    #else
    static let disableVideoAPIFetching = false
    #endif
    
    /// Number of videos to fetch per channel on refresh
    static let videosPerChannel = 20
    
    /// Number of videos to fetch per channel on incremental refresh
    static let videosPerChannelIncremental = 5
    
    /// Background task identifier
    static let backgroundTaskIdentifier = "com.metube.app.refresh"
    
    /// Minimum interval between background refreshes (in seconds)
    static let backgroundRefreshInterval: TimeInterval = 15 * 60 // 15 minutes
    
    /// Interval for forcing a full refresh (24 hours)
    static let fullRefreshInterval: TimeInterval = 24 * 60 * 60
    
    /// Daily quota limit (YouTube default is 10,000)
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
    
    // MARK: - Public Methods
    
    /// Performs a full refresh of the feed (subscriptions and all videos)
    /// Use this on first launch or when user explicitly requests full refresh
    func fullRefresh(accessToken: String) async {
        appLog("Starting full refresh", category: .feed, level: .info)
        
        guard !quotaInfo.isExceeded else {
            appLog("Full refresh blocked - quota exceeded", category: .feed, level: .warning)
            error = "API quota exceeded. Quota resets at midnight Pacific Time."
            return
        }
        
        loadingState = .loadingSubscriptions(progress: "")
        error = nil
        newVideosCount = 0
        
        do {
            // 1. Fetch all subscriptions with pagination
            appLog("Fetching subscriptions", category: .youtube, level: .info)
            loadingState = .loadingSubscriptions(progress: "Fetching channels...")
            let fetchedChannels = try await youtubeService.fetchSubscriptions(accessToken: accessToken)
            channels = fetchedChannels.sorted { $0.name.lowercased() < $1.name.lowercased() }
            appLog("Fetched \(channels.count) channels", category: .youtube, level: .success)
            
            // Estimate quota: ~1 per 50 subscriptions + 1 per channel for uploads playlist
            let subscriptionQuota = (channels.count / 50) + 1 + (channels.count / 50) + 1
            addQuotaUsage(subscriptionQuota)
            
            // 2. Load existing video statuses from CloudKit
            appLog("Loading video statuses from CloudKit", category: .cloudKit, level: .info)
            loadingState = .loadingStatuses
            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
            appLog("Loaded \(videoStatusCache.count) video statuses from CloudKit", category: .cloudKit, level: .success)
            
            // Store existing video IDs for comparison
            existingVideoIds = Set(allVideos.map { $0.id })
            
            // 3. Fetch videos from all channels with progress tracking
            appLog("Fetching videos from \(channels.count) channels", category: .youtube, level: .info)
            var newVideos: [Video] = []
            var channelIndex = 0
            let totalChannels = channels.count
            
            // Process channels in batches to show progress and manage quota
            let batchSize = 10
            for batchStart in stride(from: 0, to: channels.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, channels.count)
                let batch = Array(channels[batchStart..<batchEnd])
                
                appLog("Processing batch \(batchStart/batchSize + 1): channels \(batchStart+1)-\(batchEnd)", category: .feed, level: .debug)
                
                await withTaskGroup(of: (Int, [Video]).self) { group in
                    for (index, channel) in batch.enumerated() {
                        let absoluteIndex = batchStart + index
                        group.addTask { [youtubeService] in
                            do {
                                let videos = try await youtubeService.fetchChannelVideos(
                                    channel: channel,
                                    accessToken: accessToken,
                                    maxResults: FeedConfig.videosPerChannel
                                )
                                return (absoluteIndex, videos)
                            } catch {
                                appLog("Error fetching videos for \(channel.name): \(error)", category: .youtube, level: .error)
                                return (absoluteIndex, [])
                            }
                        }
                    }
                    
                    for await (index, videos) in group {
                        channelIndex = max(channelIndex, index + 1)
                        loadingState = .loadingVideos(
                            channelIndex: channelIndex,
                            totalChannels: totalChannels,
                            channelName: channels[min(index, channels.count - 1)].name
                        )
                        newVideos.append(contentsOf: videos)
                    }
                }
                
                // Estimate quota: ~1 per playlist fetch + 1 per 50 videos for duration
                let batchQuota = batch.count + (newVideos.count / 50) + 1
                addQuotaUsage(batchQuota)
                
                // Check quota after each batch
                if quotaInfo.isExceeded {
                    appLog("Quota exceeded during batch processing", category: .feed, level: .warning)
                    error = "API quota limit reached. Some channels may not have been loaded."
                    break
                }
            }
            
            appLog("Fetched \(newVideos.count) total videos", category: .youtube, level: .success)
            
            // 4. Apply cached statuses and count new videos
            var newCount = 0
            for i in 0..<newVideos.count {
                if let cachedStatus = videoStatusCache[newVideos[i].id] {
                    newVideos[i].status = cachedStatus
                }
                if !existingVideoIds.contains(newVideos[i].id) {
                    newCount += 1
                }
            }
            
            allVideos = newVideos
            newVideosCount = newCount
            loadingState = .idle
            
            // Save refresh timestamp and cached data
            lastRefreshDate = Date()
            appSettings.lastFullRefreshDate = Date()
            saveCachedData()
            
            appLog("Full refresh completed", category: .feed, level: .success, context: [
                "totalVideos": allVideos.count,
                "newVideos": newCount,
                "channels": channels.count
            ])
            
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
    
    /// Performs an incremental refresh - only fetches recent videos to find new content
    /// More quota-efficient than full refresh
    func incrementalRefresh(accessToken: String) async {
        appLog("Starting incremental refresh", category: .feed, level: .info, context: [
            "cachedChannels": channels.count,
            "cachedVideos": allVideos.count
        ])
        
        guard !quotaInfo.isExceeded else {
            appLog("Incremental refresh blocked - quota exceeded", category: .feed, level: .warning)
            error = "API quota exceeded. Quota resets at midnight Pacific Time."
            return
        }
        
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
        
        appLog("Proceeding with incremental refresh for \(channels.count) channels", category: .feed, level: .info)
        loadingState = .refreshing
        error = nil
        newVideosCount = 0
        
        do {
            // Store existing video IDs for comparison
            existingVideoIds = Set(allVideos.map { $0.id })
            appLog("Existing video IDs count: \(existingVideoIds.count)", category: .feed, level: .debug)
            
            // Fetch only recent videos from each channel
            var newVideos: [Video] = []
            
            await withTaskGroup(of: [Video].self) { group in
                for channel in channels {
                    group.addTask { [youtubeService] in
                        do {
                            return try await youtubeService.fetchChannelVideos(
                                channel: channel,
                                accessToken: accessToken,
                                maxResults: FeedConfig.videosPerChannelIncremental
                            )
                        } catch {
                            appLog("Error fetching videos for \(channel.name): \(error)", category: .youtube, level: .error)
                            return []
                        }
                    }
                }
                
                for await videos in group {
                    newVideos.append(contentsOf: videos)
                }
            }
            
            appLog("Fetched \(newVideos.count) videos in incremental refresh", category: .youtube, level: .info)
            
            // Estimate and track quota
            let quotaUsed = channels.count + (newVideos.count / 50) + 1
            addQuotaUsage(quotaUsed)
            
            // Load video statuses
            appLog("Loading video statuses from CloudKit", category: .cloudKit, level: .info)
            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
            appLog("Loaded \(videoStatusCache.count) video statuses", category: .cloudKit, level: .success)
            
            // Merge new videos with existing, avoiding duplicates
            var videoDict: [String: Video] = [:]
            for video in allVideos {
                videoDict[video.id] = video
            }
            
            var newCount = 0
            for var video in newVideos {
                if let cachedStatus = videoStatusCache[video.id] {
                    video.status = cachedStatus
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
            
            appLog("Incremental refresh completed", category: .feed, level: .success, context: [
                "totalVideos": allVideos.count,
                "newVideos": newCount
            ])
            
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
            "channelCount": channels.count,
            "apiDisabled": FeedConfig.disableVideoAPIFetching
        ])
        
        // Check if API fetching is disabled (for quota preservation during testing)
        if FeedConfig.disableVideoAPIFetching {
            appLog("Video API fetching is DISABLED - using CloudKit cache only", category: .feed, level: .warning)
            // Just ensure we have CloudKit data loaded
            if allVideos.isEmpty {
                appLog("No cached videos - attempting to load from CloudKit", category: .feed, level: .info)
                // Trigger a cache reload
                loadCachedData()
            }
            return
        }
        
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
        appLog("Force full refresh requested", category: .feed, level: .info, context: [
            "apiDisabled": FeedConfig.disableVideoAPIFetching
        ])
        
        // Check if API fetching is disabled
        if FeedConfig.disableVideoAPIFetching {
            appLog("Video API fetching is DISABLED - skipping full refresh", category: .feed, level: .warning)
            return
        }
        
        await fullRefresh(accessToken: accessToken)
    }
    
    /// Loads only video statuses from CloudKit (for when videos are already loaded)
    func loadVideoStatuses() async {
        appLog("Loading video statuses", category: .cloudKit, level: .info)
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
    func performBackgroundRefresh(accessToken: String) async -> Bool {
        guard !quotaInfo.isExceeded else {
            return false
        }
        
        loadingState = .backgroundRefreshing
        
        // Only fetch very recent videos in background
        var newVideos: [Video] = []

        await withTaskGroup(of: [Video].self) { group in
            for channel in channels {
                group.addTask { [youtubeService] in
                    do {
                        return try await youtubeService.fetchChannelVideos(
                            channel: channel,
                            accessToken: accessToken,
                            maxResults: 3 // Very limited in background
                        )
                    } catch {
                        return []
                    }
                }
            }

            for await videos in group {
                newVideos.append(contentsOf: videos)
            }
        }

        // Merge new videos
        let existingIds = Set(allVideos.map { $0.id })
        var newCount = 0

        for var video in newVideos {
            if let cachedStatus = videoStatusCache[video.id] {
                video.status = cachedStatus
            }

            if !existingIds.contains(video.id) {
                allVideos.append(video)
                newCount += 1
            }
        }

        newVideosCount += newCount
        loadingState = .idle
        lastRefreshDate = Date()
        saveCachedData()

        return newCount > 0
    }
}
