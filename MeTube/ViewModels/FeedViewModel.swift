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
    /// Number of videos to fetch per channel on refresh
    static let videosPerChannel = 20
    
    /// Number of videos to fetch per channel on incremental refresh
    static let videosPerChannelIncremental = 5
    
    /// Background task identifier
    static let backgroundTaskIdentifier = "com.metube.app.refresh"
    
    /// Minimum interval between background refreshes (in seconds)
    static let backgroundRefreshInterval: TimeInterval = 15 * 60 // 15 minutes
    
    /// Key for storing last refresh date
    static let lastRefreshDateKey = "com.metube.lastRefreshDate"
    
    /// Key for storing last full refresh date
    static let lastFullRefreshDateKey = "com.metube.lastFullRefreshDate"
    
    /// Interval for forcing a full refresh (24 hours)
    static let fullRefreshInterval: TimeInterval = 24 * 60 * 60
    
    /// Key for storing API quota usage
    static let quotaUsageKey = "com.metube.quotaUsage"
    
    /// Key for storing quota reset date
    static let quotaResetDateKey = "com.metube.quotaResetDate"
    
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
    
    // MARK: - Initialization
    
    init() {
        loadQuotaInfo()
        loadLastRefreshDate()
    }
    
    // MARK: - Public Methods
    
    /// Performs a full refresh of the feed (subscriptions and all videos)
    /// Use this on first launch or when user explicitly requests full refresh
    func fullRefresh(accessToken: String) async {
        guard !quotaInfo.isExceeded else {
            error = "API quota exceeded. Quota resets at midnight Pacific Time."
            return
        }
        
        loadingState = .loadingSubscriptions(progress: "")
        error = nil
        newVideosCount = 0
        
        do {
            // 1. Fetch all subscriptions with pagination
            loadingState = .loadingSubscriptions(progress: "Fetching channels...")
            let fetchedChannels = try await youtubeService.fetchSubscriptions(accessToken: accessToken)
            channels = fetchedChannels.sorted { $0.name.lowercased() < $1.name.lowercased() }
            
            // Estimate quota: ~1 per 50 subscriptions + 1 per channel for uploads playlist
            let subscriptionQuota = (channels.count / 50) + 1 + (channels.count / 50) + 1
            addQuotaUsage(subscriptionQuota)
            
            // 2. Load existing video statuses from CloudKit
            loadingState = .loadingStatuses
            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
            
            // Store existing video IDs for comparison
            existingVideoIds = Set(allVideos.map { $0.id })
            
            // 3. Fetch videos from all channels with progress tracking
            var newVideos: [Video] = []
            var channelIndex = 0
            let totalChannels = channels.count
            
            // Process channels in batches to show progress and manage quota
            let batchSize = 10
            for batchStart in stride(from: 0, to: channels.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, channels.count)
                let batch = Array(channels[batchStart..<batchEnd])
                
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
                                print("Error fetching videos for \(channel.name): \(error)")
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
                    error = "API quota limit reached. Some channels may not have been loaded."
                    break
                }
            }
            
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
            
            // Save refresh timestamp
            lastRefreshDate = Date()
            saveLastRefreshDate()
            UserDefaults.standard.set(Date(), forKey: FeedConfig.lastFullRefreshDateKey)
            
        } catch let apiError as YouTubeAPIError {
            handleAPIError(apiError)
            loadingState = .idle
        } catch {
            self.error = error.localizedDescription
            loadingState = .idle
        }
    }
    
    /// Performs an incremental refresh - only fetches recent videos to find new content
    /// More quota-efficient than full refresh
    func incrementalRefresh(accessToken: String) async {
        guard !quotaInfo.isExceeded else {
            error = "API quota exceeded. Quota resets at midnight Pacific Time."
            return
        }
        
        // If we have no data, do a full refresh
        guard !channels.isEmpty else {
            await fullRefresh(accessToken: accessToken)
            return
        }
        
        // Check if we need a full refresh (once per day)
        if shouldDoFullRefresh() {
            await fullRefresh(accessToken: accessToken)
            return
        }
        
        loadingState = .refreshing
        error = nil
        newVideosCount = 0
        
        do {
            // Store existing video IDs for comparison
            existingVideoIds = Set(allVideos.map { $0.id })
            
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
                            print("Error fetching videos for \(channel.name): \(error)")
                            return []
                        }
                    }
                }
                
                for await videos in group {
                    newVideos.append(contentsOf: videos)
                }
            }
            
            // Estimate and track quota
            let quotaUsed = channels.count + (newVideos.count / 50) + 1
            addQuotaUsage(quotaUsed)
            
            // Load video statuses
            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
            
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
            
            // Save refresh timestamp
            lastRefreshDate = Date()
            saveLastRefreshDate()
            
        } catch let apiError as YouTubeAPIError {
            handleAPIError(apiError)
            loadingState = .idle
        } catch {
            self.error = error.localizedDescription
            loadingState = .idle
        }
    }
    
    /// Refreshes the feed - uses incremental if data exists, full otherwise
    func refreshFeed(accessToken: String) async {
        if allVideos.isEmpty || channels.isEmpty {
            await fullRefresh(accessToken: accessToken)
        } else {
            await incrementalRefresh(accessToken: accessToken)
        }
    }
    
    /// Forces a full refresh regardless of existing data
    func forceFullRefresh(accessToken: String) async {
        await fullRefresh(accessToken: accessToken)
    }
    
    /// Loads only video statuses from CloudKit (for when videos are already loaded)
    func loadVideoStatuses() async {
        do {
            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
            
            // Apply cached statuses to existing videos
            for i in 0..<allVideos.count {
                if let cachedStatus = videoStatusCache[allVideos[i].id] {
                    allVideos[i].status = cachedStatus
                }
            }
        } catch {
            print("Error loading video statuses: \(error)")
        }
    }
    
    /// Marks a video as watched
    func markAsWatched(_ video: Video) async {
        await updateVideoStatus(video, newStatus: .watched)
    }
    
    /// Marks a video as skipped
    func markAsSkipped(_ video: Video) async {
        await updateVideoStatus(video, newStatus: .skipped)
    }
    
    /// Marks a video as unwatched
    func markAsUnwatched(_ video: Video) async {
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
    
    private func loadQuotaInfo() {
        let usedToday = UserDefaults.standard.integer(forKey: FeedConfig.quotaUsageKey)
        let resetDate = UserDefaults.standard.object(forKey: FeedConfig.quotaResetDateKey) as? Date ?? Date()
        
        // Check if quota should be reset (new day in Pacific Time)
        if shouldResetQuota(lastResetDate: resetDate) {
            quotaInfo = QuotaInfo(usedToday: 0, resetDate: nextQuotaResetDate())
            saveQuotaInfo()
        } else {
            quotaInfo = QuotaInfo(usedToday: usedToday, resetDate: resetDate)
        }
    }
    
    private func addQuotaUsage(_ units: Int) {
        quotaInfo.usedToday += units
        saveQuotaInfo()
    }
    
    private func saveQuotaInfo() {
        UserDefaults.standard.set(quotaInfo.usedToday, forKey: FeedConfig.quotaUsageKey)
        UserDefaults.standard.set(quotaInfo.resetDate, forKey: FeedConfig.quotaResetDateKey)
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
    
    private func loadLastRefreshDate() {
        lastRefreshDate = UserDefaults.standard.object(forKey: FeedConfig.lastRefreshDateKey) as? Date
    }
    
    private func saveLastRefreshDate() {
        UserDefaults.standard.set(lastRefreshDate, forKey: FeedConfig.lastRefreshDateKey)
    }
    
    private func shouldDoFullRefresh() -> Bool {
        guard let lastFullRefresh = UserDefaults.standard.object(forKey: FeedConfig.lastFullRefreshDateKey) as? Date else {
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
            saveQuotaInfo()
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
        saveLastRefreshDate()

        return newCount > 0
    }
}
