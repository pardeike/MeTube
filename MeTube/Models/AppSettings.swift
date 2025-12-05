//
//  AppSettings.swift
//  MeTube
//
//  Model representing app-wide settings stored in CloudKit for cross-device sync
//

import Foundation
import CloudKit

/// App-wide settings that sync across devices via CloudKit
struct AppSettings: Codable {
    /// Google OAuth Client ID
    var googleClientId: String?
    
    /// Token expiration date
    var tokenExpiration: Date?
    
    /// Last time the feed was refreshed
    var lastRefreshDate: Date?
    
    /// Last time a full refresh was performed
    var lastFullRefreshDate: Date?
    
    /// API quota used today
    var quotaUsedToday: Int
    
    /// Date when quota resets
    var quotaResetDate: Date?
    
    /// Default settings
    static var `default`: AppSettings {
        AppSettings(
            googleClientId: nil,
            tokenExpiration: nil,
            lastRefreshDate: nil,
            lastFullRefreshDate: nil,
            quotaUsedToday: 0,
            quotaResetDate: nil
        )
    }
    
    // MARK: - CloudKit Record Conversion
    
    static let recordType = "AppSettings"
    /// Use a fixed record ID so there's only one settings record per user
    static let recordId = CKRecord.ID(recordName: "app_settings")
    
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: AppSettings.recordType, recordID: AppSettings.recordId)
        record["googleClientId"] = googleClientId
        record["tokenExpiration"] = tokenExpiration
        record["lastRefreshDate"] = lastRefreshDate
        record["lastFullRefreshDate"] = lastFullRefreshDate
        record["quotaUsedToday"] = quotaUsedToday
        record["quotaResetDate"] = quotaResetDate
        return record
    }
    
    init(googleClientId: String? = nil, tokenExpiration: Date? = nil, lastRefreshDate: Date? = nil, lastFullRefreshDate: Date? = nil, quotaUsedToday: Int = 0, quotaResetDate: Date? = nil) {
        self.googleClientId = googleClientId
        self.tokenExpiration = tokenExpiration
        self.lastRefreshDate = lastRefreshDate
        self.lastFullRefreshDate = lastFullRefreshDate
        self.quotaUsedToday = quotaUsedToday
        self.quotaResetDate = quotaResetDate
    }
    
    init(from record: CKRecord) {
        self.googleClientId = record["googleClientId"] as? String
        self.tokenExpiration = record["tokenExpiration"] as? Date
        self.lastRefreshDate = record["lastRefreshDate"] as? Date
        self.lastFullRefreshDate = record["lastFullRefreshDate"] as? Date
        self.quotaUsedToday = record["quotaUsedToday"] as? Int ?? 0
        self.quotaResetDate = record["quotaResetDate"] as? Date
    }
}
