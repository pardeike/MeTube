//
//  StatusEntity.swift
//  MeTube
//
//  SwiftData entity for video watch status (offline-first architecture)
//

import Foundation
import SwiftData

/// Watch status enum for StatusEntity
enum WatchStatus: String, Codable {
    case unknown    // Status not yet determined (new video before CloudKit sync)
    case unwatched  // Not yet viewed
    case watched    // User has watched this video
    case skipped    // User chose to skip this video
}

/// SwiftData entity representing a video's watch status
@Model
final class StatusEntity {
    // MARK: - Core Properties
    
    /// Video ID this status refers to (unique key)
    var videoId: String = ""
    
    /// Current watch status
    var status: String = WatchStatus.unknown.rawValue  // Store as String for SwiftData compatibility
    
    /// Last playback position in seconds (for resume functionality)
    var playbackPosition: Double = 0
    
    // MARK: - Persistence Metadata
    
    /// When the status was last modified
    var lastModified: Date = Date()
    
    /// Whether the status has been synced to CloudKit
    var synced: Bool = false
    
    // MARK: - Computed Property
    
    /// Strongly-typed status accessor
    var watchStatus: WatchStatus {
        get { WatchStatus(rawValue: status) ?? .unknown }
        set { status = newValue.rawValue }
    }
    
    // MARK: - Initialization
    
    init(
        videoId: String,
        status: WatchStatus = .unknown,
        playbackPosition: Double = 0,
        lastModified: Date = Date(),
        synced: Bool = false
    ) {
        self.videoId = videoId
        self.status = status.rawValue
        self.playbackPosition = playbackPosition
        self.lastModified = lastModified
        self.synced = synced
    }
}
