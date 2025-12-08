//
//  StatusRepository.swift
//  MeTube
//
//  Repository for video watch status management in the local database
//

import Foundation
import SwiftData

/// Repository for managing video watch statuses in the local SwiftData database
@MainActor
class StatusRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all statuses from the local database
    func fetchAllStatuses() throws -> [StatusEntity] {
        let descriptor = FetchDescriptor<StatusEntity>()
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch status for a specific video
    func fetchStatus(forVideoId videoId: String) throws -> StatusEntity? {
        let predicate = #Predicate<StatusEntity> { status in
            status.videoId == videoId
        }
        let descriptor = FetchDescriptor<StatusEntity>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    /// Fetch all statuses that haven't been synced to CloudKit
    func fetchUnsyncedStatuses() throws -> [StatusEntity] {
        let predicate = #Predicate<StatusEntity> { status in
            status.synced == false
        }
        let descriptor = FetchDescriptor<StatusEntity>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch statuses with a specific watch status
    func fetchStatuses(withStatus status: WatchStatus) throws -> [StatusEntity] {
        let statusString = status.rawValue
        let predicate = #Predicate<StatusEntity> { entity in
            entity.status == statusString
        }
        let descriptor = FetchDescriptor<StatusEntity>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Update Operations
    
    /// Update or create a status for a video
    /// - Parameters:
    ///   - videoId: The video ID
    ///   - status: The new watch status
    ///   - synced: Whether the status has been synced to CloudKit
    @discardableResult
    func updateStatus(forVideoId videoId: String, status: WatchStatus, synced: Bool = false) throws -> StatusEntity {
        if let existingStatus = try? fetchStatus(forVideoId: videoId) {
            // Update existing status
            existingStatus.watchStatus = status
            existingStatus.lastModified = Date()
            existingStatus.synced = synced
            try modelContext.save()
            return existingStatus
        } else {
            // Create new status
            let newStatus = StatusEntity(videoId: videoId, status: status, synced: synced)
            modelContext.insert(newStatus)
            try modelContext.save()
            return newStatus
        }
    }
    
    /// Mark a status as synced to CloudKit
    func markAsSynced(videoId: String) throws {
        if let status = try fetchStatus(forVideoId: videoId) {
            status.synced = true
            try modelContext.save()
        }
    }
    
    /// Mark multiple statuses as synced
    func markAsSynced(videoIds: [String]) throws {
        for videoId in videoIds {
            try markAsSynced(videoId: videoId)
        }
    }
    
    /// Save or update a status entity
    func saveStatus(_ status: StatusEntity) throws {
        // Don't use try? here - we need to know if the fetch actually failed
        let existingStatus = try fetchStatus(forVideoId: status.videoId)
        
        if let existingStatus = existingStatus {
            existingStatus.status = status.status
            existingStatus.lastModified = status.lastModified
            existingStatus.synced = status.synced
        } else {
            modelContext.insert(status)
        }
        try modelContext.save()
    }
    
    /// Save multiple status entities
    func saveStatuses(_ statuses: [StatusEntity]) throws {
        // Deduplicate statuses by videoId to prevent inserting duplicates
        var seenIds = Set<String>()
        let uniqueStatuses = statuses.filter { status in
            if seenIds.contains(status.videoId) {
                return false
            }
            seenIds.insert(status.videoId)
            return true
        }
        
        for status in uniqueStatuses {
            try saveStatus(status)
        }
    }
    
    // MARK: - Delete Operations
    
    /// Delete a status by video ID
    func deleteStatus(forVideoId videoId: String) throws {
        if let status = try fetchStatus(forVideoId: videoId) {
            modelContext.delete(status)
            try modelContext.save()
        }
    }
    
    /// Delete all statuses
    func deleteAllStatuses() throws {
        let statuses = try fetchAllStatuses()
        for status in statuses {
            modelContext.delete(status)
        }
        try modelContext.save()
    }
    
    // MARK: - Utility
    
    /// Get a dictionary of all statuses keyed by video ID
    func fetchStatusDictionary() throws -> [String: WatchStatus] {
        let statuses = try fetchAllStatuses()
        var dict: [String: WatchStatus] = [:]
        for status in statuses {
            dict[status.videoId] = status.watchStatus
        }
        return dict
    }
    
    /// Count total number of statuses
    func count() throws -> Int {
        let descriptor = FetchDescriptor<StatusEntity>()
        return try modelContext.fetchCount(descriptor)
    }
}
