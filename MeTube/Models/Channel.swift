//
//  Channel.swift
//  MeTube
//
//  Model representing a YouTube channel subscription
//

import Foundation
import CloudKit

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
    
    // MARK: - CloudKit Record Conversion
    
    static let recordType = "Channel"
    
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: Channel.recordType, recordID: CKRecord.ID(recordName: id))
        record["name"] = name
        record["thumbnailURL"] = thumbnailURL?.absoluteString
        record["description"] = description
        record["uploadsPlaylistId"] = uploadsPlaylistId
        return record
    }
    
    init?(from record: CKRecord) {
        guard let name = record["name"] as? String else { return nil }
        
        self.id = record.recordID.recordName
        self.name = name
        
        if let urlString = record["thumbnailURL"] as? String {
            self.thumbnailURL = URL(string: urlString)
        } else {
            self.thumbnailURL = nil
        }
        
        self.description = record["description"] as? String
        self.uploadsPlaylistId = record["uploadsPlaylistId"] as? String
    }
}
