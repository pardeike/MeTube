//
//  ChannelEntity.swift
//  MeTube
//
//  SwiftData entity for local channel storage (offline-first architecture)
//

import Foundation
import SwiftData

/// SwiftData entity representing a YouTube channel in the local database
@Model
final class ChannelEntity {
    // MARK: - Core Properties
    
    /// YouTube channel ID (unique key)
    @Attribute(.unique) var channelId: String
    
    /// Channel name/title
    var name: String?
    
    /// Channel thumbnail/avatar URL
    var thumbnailURL: String?
    
    /// Channel description
    var channelDescription: String?
    
    /// Playlist ID for channel's uploads
    var uploadsPlaylistId: String?
    
    // MARK: - Persistence Metadata
    
    /// When the channel was first inserted into local database
    var insertedAt: Date
    
    /// When the channel metadata was last modified
    var lastModified: Date
    
    /// Whether the channel has been synced with remote services
    var synced: Bool
    
    // MARK: - Initialization
    
    init(
        channelId: String,
        name: String?,
        thumbnailURL: String?,
        channelDescription: String?,
        uploadsPlaylistId: String?,
        insertedAt: Date = Date(),
        lastModified: Date = Date(),
        synced: Bool = false
    ) {
        self.channelId = channelId
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.channelDescription = channelDescription
        self.uploadsPlaylistId = uploadsPlaylistId
        self.insertedAt = insertedAt
        self.lastModified = lastModified
        self.synced = synced
    }
}
