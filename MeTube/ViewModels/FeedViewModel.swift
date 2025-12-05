//
//  FeedViewModel.swift
//  MeTube
//
//  ViewModel for the subscription feed
//

import Foundation
import Combine

/// ViewModel for managing the subscription feed
@MainActor
class FeedViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var channels: [Channel] = []
    @Published var allVideos: [Video] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var searchText: String = ""
    @Published var selectedStatus: VideoStatus? = .unwatched
    
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
    
    // MARK: - Public Methods
    
    /// Refreshes the entire feed (subscriptions and videos)
    func refreshFeed(accessToken: String) async {
        isLoading = true
        error = nil
        
        do {
            // 1. Fetch subscriptions
            let fetchedChannels = try await youtubeService.fetchSubscriptions(accessToken: accessToken)
            channels = fetchedChannels.sorted { $0.name.lowercased() < $1.name.lowercased() }
            
            // 2. Load existing video statuses from CloudKit
            videoStatusCache = try await cloudKitService.fetchAllVideoStatuses()
            
            // 3. Fetch videos from all channels concurrently
            var newVideos: [Video] = []
            
            await withTaskGroup(of: [Video].self) { group in
                for channel in channels {
                    group.addTask { [youtubeService] in
                        do {
                            return try await youtubeService.fetchChannelVideos(
                                channel: channel,
                                accessToken: accessToken,
                                maxResults: 10
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
            
            // 4. Apply cached statuses
            for i in 0..<newVideos.count {
                if let cachedStatus = videoStatusCache[newVideos[i].id] {
                    newVideos[i].status = cachedStatus
                }
            }
            
            allVideos = newVideos
            isLoading = false
            
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
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
}
