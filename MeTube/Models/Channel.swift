//
//  Channel.swift
//  MeTube
//
//  Model representing a YouTube channel subscription
//

import Foundation

/// Represents a YouTube channel that the user is subscribed to
struct Channel: Identifiable, Codable, Hashable {
    let id: String              // YouTube channel ID
    let name: String            // Channel title/name
    let thumbnailURL: URL?      // Channel avatar/thumbnail
    let description: String?    // Channel description
    var uploadsPlaylistId: String? // The playlist ID for channel's uploads
    
    init(id: String, name: String, thumbnailURL: URL? = nil, description: String? = nil, uploadsPlaylistId: String? = nil) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.description = description
        self.uploadsPlaylistId = uploadsPlaylistId
    }
}
