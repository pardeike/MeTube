//
//  VideoEntity.swift
//  MeTube
//
//  SwiftData entity for local video storage (offline-first architecture)
//

import Foundation
import SwiftData

/// SwiftData entity representing a YouTube video in the local database
/// This is the single source of truth for video data in the offline-first architecture
@Model
final class VideoEntity {
    // MARK: - Core Properties
    
    /// YouTube video ID (unique key)
    var videoId: String = ""
    
    /// Channel that uploaded the video
    var channelId: String = ""
    
    /// Video title
    var title: String?
    
    /// Video description
    var videoDescription: String?
    
    /// Thumbnail URL
    var thumbnailURL: String?
    
    /// Video duration in seconds
    var duration: Double?
    
    /// When the video was published on YouTube
    var publishedAt: Date = Date()
    
    // MARK: - Persistence Metadata
    
    /// When the video was first inserted into local database
    var insertedAt: Date = Date()
    
    /// When the video metadata was last modified
    var lastModified: Date = Date()
    
    /// Whether the video has been synced with remote services
    var synced: Bool = false
    
    // MARK: - Initialization
    
    init(
        videoId: String,
        channelId: String,
        title: String?,
        videoDescription: String?,
        thumbnailURL: String?,
        duration: Double?,
        publishedAt: Date,
        insertedAt: Date = Date(),
        lastModified: Date = Date(),
        synced: Bool = false
    ) {
        self.videoId = videoId
        self.channelId = channelId
        self.title = title
        self.videoDescription = videoDescription
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.publishedAt = publishedAt
        self.insertedAt = insertedAt
        self.lastModified = lastModified
        self.synced = synced
    }
}
