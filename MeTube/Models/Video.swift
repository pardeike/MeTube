//
//  Video.swift
//  MeTube
//
//  Model representing a YouTube video
//

import Foundation
import CloudKit

/// Status of a video from the user's perspective
enum VideoStatus: String, Codable, CaseIterable {
    case unwatched  // Not yet viewed
    case watched    // User has watched this video
    case skipped    // User chose to skip this video
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
    
    // MARK: - CloudKit Record Conversion
    
    static let recordType = "Video"
    
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: Video.recordType, recordID: CKRecord.ID(recordName: id))
        record["title"] = title
        record["channelId"] = channelId
        record["channelName"] = channelName
        record["publishedDate"] = publishedDate
        record["duration"] = duration
        record["thumbnailURL"] = thumbnailURL?.absoluteString
        record["description"] = description
        record["status"] = status.rawValue
        return record
    }
    
    init?(from record: CKRecord) {
        guard let title = record["title"] as? String,
              let channelId = record["channelId"] as? String,
              let channelName = record["channelName"] as? String,
              let publishedDate = record["publishedDate"] as? Date,
              let duration = record["duration"] as? TimeInterval,
              let statusString = record["status"] as? String,
              let status = VideoStatus(rawValue: statusString) else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.title = title
        self.channelId = channelId
        self.channelName = channelName
        self.publishedDate = publishedDate
        self.duration = duration
        self.status = status
        
        if let urlString = record["thumbnailURL"] as? String {
            self.thumbnailURL = URL(string: urlString)
        } else {
            self.thumbnailURL = nil
        }
        
        self.description = record["description"] as? String
    }
}
