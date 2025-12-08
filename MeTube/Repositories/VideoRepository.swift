//
//  VideoRepository.swift
//  MeTube
//
//  Repository for video CRUD operations in the local database
//

import Foundation
import SwiftData
import Combine

/// Repository for managing videos in the local SwiftData database
@MainActor
class VideoRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all videos from the local database
    func fetchAllVideos() throws -> [VideoEntity] {
        let descriptor = FetchDescriptor<VideoEntity>(
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch videos for a specific channel
    func fetchVideos(forChannelId channelId: String) throws -> [VideoEntity] {
        let predicate = #Predicate<VideoEntity> { video in
            video.channelId == channelId
        }
        let descriptor = FetchDescriptor<VideoEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch a video by its ID
    func fetchVideo(byId videoId: String) throws -> VideoEntity? {
        let predicate = #Predicate<VideoEntity> { video in
            video.videoId == videoId
        }
        let descriptor = FetchDescriptor<VideoEntity>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    /// Fetch videos published after a specific date
    func fetchVideos(publishedAfter date: Date) throws -> [VideoEntity] {
        let predicate = #Predicate<VideoEntity> { video in
            video.publishedAt > date
        }
        let descriptor = FetchDescriptor<VideoEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Save Operations
    
    /// Save or update a video in the database
    /// - Parameter video: The video entity to save
    /// - Returns: The saved video entity
    @discardableResult
    func saveVideo(_ video: VideoEntity) throws -> VideoEntity {
        // Check if video already exists
        if let existingVideo = try? fetchVideo(byId: video.videoId) {
            // Update existing video
            existingVideo.title = video.title
            existingVideo.videoDescription = video.videoDescription
            existingVideo.thumbnailURL = video.thumbnailURL
            existingVideo.duration = video.duration
            existingVideo.publishedAt = video.publishedAt
            existingVideo.lastModified = Date()
            existingVideo.synced = video.synced
            
            try modelContext.save()
            return existingVideo
        } else {
            // Insert new video
            modelContext.insert(video)
            try modelContext.save()
            return video
        }
    }
    
    /// Save multiple videos in a batch
    func saveVideos(_ videos: [VideoEntity]) throws {
        for video in videos {
            try saveVideo(video)
        }
    }
    
    /// Merge videos from remote source, deduplicating by videoId
    /// - Parameter videos: Array of video entities to merge
    /// - Returns: Number of new videos added
    func mergeVideos(_ videos: [VideoEntity]) throws -> Int {
        var newCount = 0
        for video in videos {
            if (try? fetchVideo(byId: video.videoId)) == nil {
                modelContext.insert(video)
                newCount += 1
            }
        }
        try modelContext.save()
        return newCount
    }
    
    // MARK: - Delete Operations
    
    /// Delete a video by its ID
    func deleteVideo(byId videoId: String) throws {
        if let video = try fetchVideo(byId: videoId) {
            modelContext.delete(video)
            try modelContext.save()
        }
    }
    
    /// Delete all videos
    func deleteAllVideos() throws {
        let videos = try fetchAllVideos()
        for video in videos {
            modelContext.delete(video)
        }
        try modelContext.save()
    }
    
    // MARK: - Utility
    
    /// Count total number of videos
    func count() throws -> Int {
        let descriptor = FetchDescriptor<VideoEntity>()
        return try modelContext.fetchCount(descriptor)
    }
}
