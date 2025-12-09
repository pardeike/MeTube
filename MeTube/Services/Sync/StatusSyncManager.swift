//
//  StatusSyncManager.swift
//  MeTube
//
//  Manager for synchronizing watch status with CloudKit
//  Implements incremental sync with change tokens
//

import Foundation
import CloudKit
import SwiftData

/// Configuration for status sync operations
enum StatusSyncConfig {
    /// Minimum interval between syncs (in seconds)
    static let minimumSyncInterval: TimeInterval = 5 * 60 // 5 minutes
    
    /// Maximum batch size for CloudKit operations (avoid throttling)
    static let maxBatchSize = 400
    
    /// UserDefaults key for last status sync timestamp
    static let lastStatusSyncKey = "lastStatusSync"
    
    /// UserDefaults key for CloudKit change token
    static let changeTokenKey = "cloudKitStatusChangeToken"
    
    /// CloudKit zone name for watched status
    static let zoneName = "WatchedStatusZone"
    
    /// CloudKit record type for status
    static let recordType = "WatchedStatus"
    
    /// CloudKit container identifier (must match CloudKitConfig.containerIdentifier from CloudKitService)
    static let containerIdentifier = "iCloud.com.metube.app"
}

/// Manager for syncing watch status with CloudKit
@MainActor
class StatusSyncManager {
    private let statusRepository: StatusRepository
    private let cloudKitService: CloudKitService
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let userId: String
    
    /// Concurrency guard to prevent overlapping syncs
    /// Thread-safe because this class is @MainActor - all access is serialized on main actor
    private var isSyncing = false
    
    /// Last time the status was synced
    private var lastStatusSync: Date? {
        get {
            UserDefaults.standard.object(forKey: StatusSyncConfig.lastStatusSyncKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: StatusSyncConfig.lastStatusSyncKey)
        }
    }
    
    /// CloudKit change token for incremental sync
    private var changeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: StatusSyncConfig.changeTokenKey) else {
                return nil
            }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            if let token = newValue {
                let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                UserDefaults.standard.set(data, forKey: StatusSyncConfig.changeTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: StatusSyncConfig.changeTokenKey)
            }
        }
    }
    
    init(
        statusRepository: StatusRepository,
        cloudKitService: CloudKitService = CloudKitService(),
        userId: String
    ) {
        self.statusRepository = statusRepository
        self.cloudKitService = cloudKitService
        self.userId = userId
        self.container = CKContainer(identifier: StatusSyncConfig.containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
    }
    
    // MARK: - Sync Operations
    
    /// Check if sync is needed based on last sync time
    func shouldSync() -> Bool {
        guard let lastSync = lastStatusSync else {
            appLog("No previous status sync found, sync needed", category: .cloudKit, level: .info)
            return true
        }
        
        let elapsed = Date().timeIntervalSince(lastSync)
        let shouldSync = elapsed >= StatusSyncConfig.minimumSyncInterval
        
        if shouldSync {
            appLog("Last status sync was \(Int(elapsed))s ago, sync needed", category: .cloudKit, level: .debug)
        }
        
        return shouldSync
    }
    
    /// Perform sync if needed (non-blocking check)
    /// - Returns: Tuple of (pulled: Int, pushed: Int) representing number of statuses synced, or (0, 0) if sync was not needed
    func syncIfNeeded() async throws -> (pulled: Int, pushed: Int) {
        // Check if already syncing
        guard !isSyncing else {
            appLog("Status sync already in progress, skipping", category: .cloudKit, level: .debug)
            return (0, 0)
        }
        
        // Check iCloud availability first
        guard await cloudKitService.checkiCloudStatus() else {
            appLog("iCloud not available, skipping status sync", category: .cloudKit, level: .warning)
            return (0, 0)
        }
        
        guard shouldSync() else {
            appLog("Status sync not needed at this time", category: .cloudKit, level: .debug)
            return (0, 0)
        }
        
        return try await performSync()
    }
    
    /// Perform a full sync operation (pull then push)
    @discardableResult
    func performSync() async throws -> (pulled: Int, pushed: Int) {
        // Check if already syncing
        guard !isSyncing else {
            appLog("Status sync already in progress, skipping", category: .cloudKit, level: .debug)
            return (0, 0)
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        appLog("Starting status sync with CloudKit", category: .cloudKit, level: .info)
        
        // 0. Ensure CloudKit zone exists before pulling
        try await ensureZoneExists()
        
        // 1. Pull changes from CloudKit
        let pulledCount = try await pullChangesFromCloudKit()
        
        // 2. Push local changes to CloudKit
        let pushedCount = try await pushChangesToCloudKit()
        
        // 3. Update last sync timestamp
        lastStatusSync = Date()
        
        appLog("Status sync completed - pulled \(pulledCount), pushed \(pushedCount)", category: .cloudKit, level: .success)
        
        return (pulled: pulledCount, pushed: pushedCount)
    }
    
    // MARK: - CloudKit Zone Management
    
    /// Ensure the CloudKit zone exists, creating it if necessary
    private func ensureZoneExists() async throws {
        let zoneID = CKRecordZone.ID(zoneName: StatusSyncConfig.zoneName)
        
        // First, check if zone exists
        do {
            let zoneExists = try await checkZoneExists(zoneID: zoneID)
            if zoneExists {
                appLog("CloudKit zone already exists", category: .cloudKit, level: .debug)
                return
            }
        } catch {
            // If we get a zone not found error or any error, try to create the zone
            appLog("Zone check failed or zone not found, will create zone", category: .cloudKit, level: .info)
        }
        
        // Zone doesn't exist, create it
        try await createZone()
    }
    
    /// Check if CloudKit zone exists
    private func checkZoneExists(zoneID: CKRecordZone.ID) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
            
            operation.fetchRecordZonesResultBlock = { result in
                switch result {
                case .success: // (let zones):
                    continuation.resume(returning: true)
                    //continuation.resume(returning: zones[zoneID] != nil)
                case .failure(let error):
                    appLog("Failed to check zone existence: \(error)", category: .cloudKit, level: .debug)
                    continuation.resume(throwing: error)
                }
            }
            
            privateDatabase.add(operation)
        }
    }
    
    /// Create the CloudKit zone for status sync
    private func createZone() async throws {
        let zoneID = CKRecordZone.ID(zoneName: StatusSyncConfig.zoneName)
        let zone = CKRecordZone(zoneID: zoneID)
        
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    appLog("Successfully created CloudKit zone", category: .cloudKit, level: .success)
                    continuation.resume()
                case .failure(let error):
                    appLog("Failed to create CloudKit zone: \(error)", category: .cloudKit, level: .error)
                    continuation.resume(throwing: CloudKitError.networkError(error))
                }
            }
            
            privateDatabase.add(operation)
        }
    }
    
    // MARK: - Pull from CloudKit
    
    /// Pull status changes from CloudKit using change tokens
    private func pullChangesFromCloudKit() async throws -> Int {
        appLog("Pulling status changes from CloudKit", category: .cloudKit, level: .info)
        
        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var newChangeToken: CKServerChangeToken?
        
        // Use CKFetchRecordZoneChangesOperation for incremental sync
        let zoneID = CKRecordZone.ID(zoneName: StatusSyncConfig.zoneName)
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = changeToken
        
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )
        
        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case .success(let record):
                changedRecords.append(record)
            case .failure(let error):
                appLog("Error fetching changed record: \(error)", category: .cloudKit, level: .error)
            }
        }
        
        operation.recordWithIDWasDeletedBlock = { recordID, recordType in
            deletedRecordIDs.append(recordID)
        }
        
        operation.recordZoneFetchResultBlock = { zoneID, result in
            switch result {
            case .success(let (token, _, _)):
                newChangeToken = token
            case .failure(let error):
                // Handle zone not found error gracefully (shouldn't happen after ensureZoneExists, but be safe)
                if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                    appLog("Zone not found during fetch - will be created on next sync", category: .cloudKit, level: .warning)
                } else {
                    appLog("Error fetching zone changes: \(error)", category: .cloudKit, level: .error)
                }
            }
        }
        
        // Execute operation
        return try await withCheckedThrowingContinuation { continuation in
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    // Update change token
                    if let token = newChangeToken {
                        self.changeToken = token
                    }
                    
                    // Process changes
                    Task {
                        do {
                            let count = try await self.processCloudKitChanges(
                                changed: changedRecords,
                                deleted: deletedRecordIDs
                            )
                            continuation.resume(returning: count)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                case .failure(let error):
                    appLog("Failed to fetch zone changes: \(error)", category: .cloudKit, level: .error)
                    continuation.resume(throwing: CloudKitError.networkError(error))
                }
            }
            
            privateDatabase.add(operation)
        }
    }
    
    /// Process CloudKit changes into local database
    private func processCloudKitChanges(
        changed: [CKRecord],
        deleted: [CKRecord.ID]
    ) async throws -> Int {
        var processedCount = 0
        
        // Process changed records
        for record in changed {
            guard let videoId = record["videoId"] as? String,
                  let statusString = record["status"] as? String,
                  let status = WatchStatus(rawValue: statusString),
                  let lastModified = record["lastModified"] as? Date else {
                appLog("Invalid status record from CloudKit", category: .cloudKit, level: .warning)
                continue
            }
            
            // Check for conflict with local changes
            if let localStatus = try statusRepository.fetchStatus(forVideoId: videoId) {
                // Use most recent lastModified to resolve conflict
                if lastModified > localStatus.lastModified {
                    // Remote is newer, update local
                    try statusRepository.updateStatus(forVideoId: videoId, status: status, synced: true)
                    processedCount += 1
                    appLog("Updated local status from CloudKit: \(videoId) -> \(status)", category: .cloudKit, level: .debug)
                } else {
                    appLog("Local status is newer, keeping local: \(videoId)", category: .cloudKit, level: .debug)
                }
            } else {
                // No local status, insert from CloudKit
                let entity = StatusEntity(videoId: videoId, status: status, lastModified: lastModified, synced: true)
                try statusRepository.saveStatus(entity)
                processedCount += 1
                appLog("Added status from CloudKit: \(videoId) -> \(status)", category: .cloudKit, level: .debug)
            }
        }
        
        // Process deleted records
        for recordID in deleted {
            let videoId = recordID.recordName
            do {
                try statusRepository.deleteStatus(forVideoId: videoId)
                processedCount += 1
                appLog("Deleted status from local database: \(videoId)", category: .cloudKit, level: .debug)
            } catch {
                appLog("Failed to delete status from local database: \(videoId) - \(error)", category: .cloudKit, level: .warning)
            }
        }
        
        appLog("Processed \(processedCount) status changes from CloudKit", category: .cloudKit, level: .success)
        return processedCount
    }
    
    // MARK: - Push to CloudKit
    
    /// Push local status changes to CloudKit
    private func pushChangesToCloudKit() async throws -> Int {
        appLog("Pushing status changes to CloudKit", category: .cloudKit, level: .info)
        
        // Fetch unsynced statuses
        let unsyncedStatuses = try statusRepository.fetchUnsyncedStatuses()
        
        guard !unsyncedStatuses.isEmpty else {
            appLog("No unsynced statuses to push", category: .cloudKit, level: .debug)
            return 0
        }
        
        appLog("Found \(unsyncedStatuses.count) unsynced statuses to push", category: .cloudKit, level: .info)
        
        // Push in batches to avoid CloudKit throttling
        var totalPushed = 0
        let batches = unsyncedStatuses.chunked(into: StatusSyncConfig.maxBatchSize)
        
        for (index, batch) in batches.enumerated() {
            appLog("Pushing batch \(index + 1)/\(batches.count) (\(batch.count) statuses)", category: .cloudKit, level: .debug)
            
            let count = try await pushBatch(batch)
            totalPushed += count
        }
        
        appLog("Pushed \(totalPushed) statuses to CloudKit", category: .cloudKit, level: .success)
        return totalPushed
    }
    
    /// Push a batch of statuses to CloudKit
    private func pushBatch(_ statuses: [StatusEntity]) async throws -> Int {
        let zoneID = CKRecordZone.ID(zoneName: StatusSyncConfig.zoneName)
        
        // Create CKRecord objects
        let records = statuses.map { status -> CKRecord in
            let recordID = CKRecord.ID(recordName: status.videoId, zoneID: zoneID)
            let record = CKRecord(recordType: StatusSyncConfig.recordType, recordID: recordID)
            record["videoId"] = status.videoId
            record["status"] = status.status
            record["userId"] = userId
            record["lastModified"] = status.lastModified
            return record
        }
        
        // Save records using CKModifyRecordsOperation
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    // Mark statuses as synced
                    Task {
                        do {
                            let videoIds = statuses.map { $0.videoId }
                            try self.statusRepository.markAsSynced(videoIds: videoIds)
                            appLog("Marked \(videoIds.count) statuses as synced", category: .cloudKit, level: .debug)
                            continuation.resume(returning: videoIds.count)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                case .failure(let error):
                    appLog("Failed to save records to CloudKit: \(error)", category: .cloudKit, level: .error)
                    continuation.resume(throwing: CloudKitError.networkError(error))
                }
            }
            
            privateDatabase.add(operation)
        }
    }
    
    // MARK: - Force Sync
    
    /// Force a sync even if the interval hasn't elapsed
    func forceSync() async throws -> (pulled: Int, pushed: Int) {
        appLog("Forcing status sync", category: .cloudKit, level: .info)
        return try await performSync()
    }
    
    /// Reset sync state (for testing or troubleshooting)
    func resetSyncState() {
        lastStatusSync = nil
        changeToken = nil
        appLog("Reset status sync state", category: .cloudKit, level: .info)
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
