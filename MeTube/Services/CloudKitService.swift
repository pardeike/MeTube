//
//  CloudKitService.swift
//  MeTube
//
//  Service for CloudKit operations to sync video status across devices
//

import Foundation
import CloudKit

enum CloudKitError: LocalizedError {
    case notAuthenticated
    case recordNotFound
    case networkError(Error)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "iCloud account not available. Please sign in to iCloud."
        case .recordNotFound:
            return "Record not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Configuration

/// CloudKit configuration constants
enum CloudKitConfig {
    /// The iCloud container identifier for the app
    /// This should match the container configured in the Apple Developer Portal
    static let containerIdentifier = "iCloud.com.metube.app"
}

/// Service for managing video watch status in CloudKit
class CloudKitService {
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    
    init(containerIdentifier: String = CloudKitConfig.containerIdentifier) {
        appLog("Initializing CloudKitService with container: \(containerIdentifier)", category: .cloudKit, level: .info)
        self.container = CKContainer(identifier: containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
    }
    
    // MARK: - iCloud Status
    
    /// Checks if iCloud is available
    func checkiCloudStatus() async -> Bool {
        appLog("Checking iCloud status", category: .cloudKit, level: .debug)
        do {
            let status = try await container.accountStatus()
            let isAvailable = status == .available
            appLog("iCloud status: \(isAvailable ? "available" : "unavailable")", category: .cloudKit, level: isAvailable ? .success : .warning)
            return isAvailable
        } catch {
            appLog("Failed to check iCloud status: \(error)", category: .cloudKit, level: .error)
            return false
        }
    }
    
    // MARK: - Video Status Operations
    
    /// Saves or updates a video's status using CKModifyRecordsOperation
    /// This is more efficient than fetching before saving
    func saveVideoStatus(_ video: Video) async throws {
        let record = video.toRecord()
        
        // Use CKModifyRecordsOperation with savePolicy to handle both insert and update
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        // .changedKeys only saves modified fields, while handling conflicts
        operation.savePolicy = .changedKeys
        operation.isAtomic = true
        
        return try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: CloudKitError.unknownError(error))
                }
            }
            
            privateDatabase.add(operation)
        }
    }
    
    /// Fetches all video statuses from CloudKit
    func fetchAllVideoStatuses() async throws -> [String: VideoStatus] {
        appLog("Fetching all video statuses from CloudKit", category: .cloudKit, level: .info)
        var statuses: [String: VideoStatus] = [:]
        
        let query = CKQuery(recordType: Video.recordType, predicate: NSPredicate(value: true))
        
        do {
            let records = try await performQuery(query)
            appLog("Fetched \(records.count) records from CloudKit", category: .cloudKit, level: .debug)
            
            for record in records {
                let videoId = record.recordID.recordName
                if let statusString = record["status"] as? String,
                   let status = VideoStatus(rawValue: statusString) {
                    statuses[videoId] = status
                }
            }
            appLog("Successfully loaded \(statuses.count) video statuses", category: .cloudKit, level: .success)
        } catch let ckError as CKError {
            // Handle "unknown item" error (record type doesn't exist yet)
            // This is expected on fresh installs before any videos are saved
            if ckError.code == .unknownItem {
                appLog("Record type doesn't exist yet (fresh install) - returning empty statuses", category: .cloudKit, level: .info)
                return [:]
            }
            appLog("CloudKit error fetching video statuses: \(ckError)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(ckError)
        } catch {
            appLog("Error fetching video statuses: \(error)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(error)
        }
        
        return statuses
    }
    
    /// Fetches video status for specific video IDs
    func fetchVideoStatuses(videoIds: [String]) async throws -> [String: VideoStatus] {
        guard !videoIds.isEmpty else { return [:] }
        
        var statuses: [String: VideoStatus] = [:]
        
        // CloudKit has a limit on IN queries, process in batches
        let batchSize = 100
        for batchStart in stride(from: 0, to: videoIds.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, videoIds.count)
            let batch = Array(videoIds[batchStart..<batchEnd])
            
            let recordIds = batch.map { CKRecord.ID(recordName: $0) }
            
            do {
                let results = try await privateDatabase.records(for: recordIds)
                
                for (recordId, result) in results {
                    if case .success(let record) = result,
                       let statusString = record["status"] as? String,
                       let status = VideoStatus(rawValue: statusString) {
                        statuses[recordId.recordName] = status
                    }
                }
            } catch {
                // Continue with partial results if some records fail
                print("Error fetching batch: \(error)")
            }
        }
        
        return statuses
    }
    
    /// Updates status for multiple videos
    func batchUpdateVideoStatuses(_ videos: [Video]) async throws {
        guard !videos.isEmpty else { return }
        
        let records = videos.map { $0.toRecord() }
        
        // Use modify operation for batch updates
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        
        return try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: CloudKitError.unknownError(error))
                }
            }
            
            privateDatabase.add(operation)
        }
    }
    
    /// Deletes a video status record
    func deleteVideoStatus(videoId: String) async throws {
        let recordId = CKRecord.ID(recordName: videoId)
        
        do {
            try await privateDatabase.deleteRecord(withID: recordId)
        } catch {
            throw CloudKitError.unknownError(error)
        }
    }
    
    // MARK: - Channel Operations
    
    /// Saves a channel to CloudKit
    func saveChannel(_ channel: Channel) async throws {
        let record = channel.toRecord()
        
        do {
            _ = try await privateDatabase.save(record)
        } catch {
            throw CloudKitError.unknownError(error)
        }
    }
    
    /// Fetches all channels from CloudKit
    func fetchAllChannels() async throws -> [Channel] {
        let query = CKQuery(recordType: Channel.recordType, predicate: NSPredicate(value: true))
        
        do {
            let records = try await performQuery(query)
            return records.compactMap { Channel(from: $0) }
        } catch let ckError as CKError {
            // Handle "unknown item" error (record type doesn't exist yet)
            // This is expected on fresh installs before any channels are saved
            if ckError.code == .unknownItem {
                return []
            }
            throw CloudKitError.networkError(ckError)
        } catch {
            throw CloudKitError.networkError(error)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func performQuery(_ query: CKQuery) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let (records, nextCursor) = try await performQueryOperation(query: query, cursor: cursor)
            allRecords.append(contentsOf: records)
            cursor = nextCursor
        } while cursor != nil
        
        return allRecords
    }
    
    private func performQueryOperation(query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        return try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            
            let operation: CKQueryOperation
            if let cursor = cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(query: query)
            }
            
            operation.resultsLimit = 100
            
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (records, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            privateDatabase.add(operation)
        }
    }
}
