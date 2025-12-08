//
//  ModelConverters.swift
//  MeTube
//
//  Converters between SwiftData entities and legacy models
//  Maintains compatibility during refactoring
//

import Foundation
import SwiftData

// MARK: - Video Conversion

extension Video {
    /// Create a Video from VideoEntity and optional StatusEntity
    init(from entity: VideoEntity, status: StatusEntity? = nil) {
        // Determine status from StatusEntity or default to unknown
        let videoStatus: VideoStatus
        if let statusEntity = status {
            videoStatus = statusEntity.watchStatus.toVideoStatus()
        } else {
            videoStatus = .unwatched
        }
        
        self.init(
            id: entity.videoId,
            title: entity.title ?? "",
            channelId: entity.channelId,
            channelName: "", // Will be populated by joining with ChannelEntity
            publishedDate: entity.publishedAt,
            duration: entity.duration ?? 0,
            thumbnailURL: entity.thumbnailURL.flatMap { URL(string: $0) },
            description: entity.videoDescription,
            status: videoStatus
        )
    }
    
    /// Create a Video from VideoEntity with ChannelEntity
    init(from videoEntity: VideoEntity, channel: ChannelEntity?, status: StatusEntity? = nil) {
        let videoStatus: VideoStatus
        if let statusEntity = status {
            videoStatus = statusEntity.watchStatus.toVideoStatus()
        } else {
            videoStatus = .unwatched
        }
        
        self.init(
            id: videoEntity.videoId,
            title: videoEntity.title ?? "",
            channelId: videoEntity.channelId,
            channelName: channel?.name ?? "",
            publishedDate: videoEntity.publishedAt,
            duration: videoEntity.duration ?? 0,
            thumbnailURL: videoEntity.thumbnailURL.flatMap { URL(string: $0) },
            description: videoEntity.videoDescription,
            status: videoStatus
        )
    }
}

// MARK: - Channel Conversion

extension Channel {
    /// Create a Channel from ChannelEntity
    init(from entity: ChannelEntity) {
        self.init(
            id: entity.channelId,
            name: entity.name ?? "",
            thumbnailURL: entity.thumbnailURL.flatMap { URL(string: $0) },
            description: entity.channelDescription,
            uploadsPlaylistId: entity.uploadsPlaylistId
        )
    }
}

extension ChannelEntity {
    /// Create a ChannelEntity from Channel
    convenience init(from channel: Channel) {
        self.init(
            channelId: channel.id,
            name: channel.name,
            thumbnailURL: channel.thumbnailURL?.absoluteString,
            channelDescription: channel.description,
            uploadsPlaylistId: channel.uploadsPlaylistId
        )
    }
}

// MARK: - Status Conversion

extension WatchStatus {
    /// Convert WatchStatus to VideoStatus for legacy compatibility
    func toVideoStatus() -> VideoStatus {
        switch self {
        case .unknown, .unwatched:
            return .unwatched
        case .watched:
            return .watched
        case .skipped:
            return .skipped
        }
    }
}

extension VideoStatus {
    /// Convert VideoStatus to WatchStatus
    func toWatchStatus() -> WatchStatus {
        switch self {
        case .unwatched:
            return .unwatched
        case .watched:
            return .watched
        case .skipped:
            return .skipped
        }
    }
}
