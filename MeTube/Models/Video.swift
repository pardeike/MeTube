//
//  Video.swift
//  MeTube
//
//  Model representing a YouTube video
//

import Foundation

/// Status of a video from the user's perspective
enum VideoStatus: String, Codable, CaseIterable {
    case unwatched  // Not yet viewed
    case watched    // User has watched this video
    case skipped    // User chose to skip this video
}

extension VideoStatus {
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

/// Represents a YouTube video from a subscribed channel
struct Video: Identifiable, Codable, Hashable {
    let id: String              // YouTube video ID
    let title: String           // Video title
    let channelId: String       // Channel that uploaded the video
    let channelName: String     // Name of the channel
    let publishedDate: Date     // When the video was published
    let duration: TimeInterval  // Video duration in seconds
    let thumbnailURL: URL?      // Video thumbnail
    let description: String?    // Video description
    var status: VideoStatus     // Watch status
    
    /// Returns true if this video is a YouTube Short (< 60 seconds)
    var isShort: Bool {
        return duration < 60
    }
    
    /// Human-readable duration string (e.g., "12:34")
    var durationString: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Human-readable relative publish date
    var relativePublishDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: publishedDate, relativeTo: Date())
    }
    
    init(id: String, title: String, channelId: String, channelName: String, publishedDate: Date, duration: TimeInterval, thumbnailURL: URL? = nil, description: String? = nil, status: VideoStatus = .unwatched) {
        self.id = id
        self.title = title
        self.channelId = channelId
        self.channelName = channelName
        self.publishedDate = publishedDate
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.description = description
        self.status = status
    }
}
