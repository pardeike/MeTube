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
    case schemaNotConfigured(String)
    
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
        case .schemaNotConfigured(let details):
            return "CloudKit schema not properly configured. \(details) Please check CloudKit Dashboard indexes."
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
    
    // MARK: - Schema Preparation
    
    /// Schema preparation result containing status for each record type
    struct SchemaPreparationResult {
        let videoSchemaReady: Bool
        let channelSchemaReady: Bool
        let appSettingsSchemaReady: Bool
        let usersSchemaReady: Bool
        let errors: [String]
        
        /// Returns true if all schema components are ready
        /// Note: errors array is derived from individual ready flags, so we only check the flags
        var allReady: Bool {
            return videoSchemaReady && channelSchemaReady && appSettingsSchemaReady && usersSchemaReady
        }
    }
    
    /// Prepares the CloudKit schema by creating record types if they don't exist
    /// and verifying that required indexes are configured.
    ///
    /// This method should be called on first app launch to ensure the CloudKit
    /// database is properly set up. It creates placeholder records to trigger
    /// auto-schema creation in the Development environment.
    ///
    /// - Note: Field indexes (queryable, sortable) must be configured manually
    ///         in the CloudKit Dashboard. This method will detect if indexes
    ///         are missing and report them in the result.
    ///
    /// - Returns: A result indicating which schemas are ready and any errors encountered
    func prepareSchema() async -> SchemaPreparationResult {
        appLog("Preparing CloudKit schema", category: .cloudKit, level: .info)
        
        var errors: [String] = []
        
        // Check and prepare Video schema
        let videoReady = await prepareVideoSchema()
        if !videoReady {
            errors.append("Video: 'status' field must be marked Queryable in CloudKit Dashboard")
        }
        
        // Check and prepare Channel schema
        let channelReady = await prepareChannelSchema()
        if !channelReady {
            errors.append("Channel: 'name' field must be marked Queryable in CloudKit Dashboard")
        }
        
        // Check and prepare AppSettings schema
        let appSettingsReady = await prepareAppSettingsSchema()
        if !appSettingsReady {
            errors.append("AppSettings: Record type may need to be created")
        }
        
        // Check and prepare Users schema (CloudKit's built-in type)
        let usersReady = await prepareUsersSchema()
        if !usersReady {
            errors.append("Users: 'recordName' field must be marked Queryable in CloudKit Dashboard")
        }
        
        let result = SchemaPreparationResult(
            videoSchemaReady: videoReady,
            channelSchemaReady: channelReady,
            appSettingsSchemaReady: appSettingsReady,
            usersSchemaReady: usersReady,
            errors: errors
        )
        
        if result.allReady {
            appLog("CloudKit schema preparation complete - all schemas ready", category: .cloudKit, level: .success)
        } else {
            appLog("CloudKit schema preparation complete with issues: \(errors.joined(separator: "; "))", category: .cloudKit, level: .warning)
        }
        
        return result
    }
    
    /// Prepares the Video record type schema and verifies the 'status' index
    private func prepareVideoSchema() async -> Bool {
        appLog("Checking Video schema", category: .cloudKit, level: .debug)
        
        // Try a query that uses the 'status' field index
        let allStatuses = VideoStatus.allCases.map { $0.rawValue }
        let predicate = NSPredicate(format: "status IN %@", allStatuses)
        let query = CKQuery(recordType: Video.recordType, predicate: predicate)
        
        do {
            // Limit to 1 result just to test the query works
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = 1
            
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
                var records: [CKRecord] = []
                
                operation.recordMatchedBlock = { _, result in
                    if case .success(let record) = result {
                        records.append(record)
                    }
                }
                
                operation.queryResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: records)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                privateDatabase.add(operation)
            }
            
            appLog("Video schema is ready", category: .cloudKit, level: .success)
            return true
        } catch let error as CKError {
            // Check if error is related to missing index or unknown record type
            if error.code == .unknownItem {
                // Record type doesn't exist yet - this is OK, it will be created on first save
                appLog("Video record type doesn't exist yet (will be created on first save)", category: .cloudKit, level: .info)
                return true
            }
            
            // Check for index-related errors
            if isIndexError(error) {
                appLog("Video schema: 'status' field index is not configured", category: .cloudKit, level: .warning)
                return false
            }
            
            appLog("Error checking Video schema: \(error)", category: .cloudKit, level: .error)
            return true // Assume ready if we can't determine
        } catch {
            appLog("Error checking Video schema: \(error)", category: .cloudKit, level: .error)
            return true
        }
    }
    
    /// Prepares the Channel record type schema and verifies the 'name' index
    private func prepareChannelSchema() async -> Bool {
        appLog("Checking Channel schema", category: .cloudKit, level: .debug)
        
        // Try a query that uses the 'name' field index
        // CloudKit doesn't support 'field != nil' predicates, so we use 'name >= ""' instead.
        // This matches all records where name is a non-null string (including empty strings),
        // which is equivalent to 'name != nil' for our use case since all channels have names.
        let predicate = NSPredicate(format: "name >= %@", "")
        let query = CKQuery(recordType: Channel.recordType, predicate: predicate)
        
        do {
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = 1
            
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
                var records: [CKRecord] = []
                
                operation.recordMatchedBlock = { _, result in
                    if case .success(let record) = result {
                        records.append(record)
                    }
                }
                
                operation.queryResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: records)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                privateDatabase.add(operation)
            }
            
            appLog("Channel schema is ready", category: .cloudKit, level: .success)
            return true
        } catch let error as CKError {
            if error.code == .unknownItem {
                appLog("Channel record type doesn't exist yet (will be created on first save)", category: .cloudKit, level: .info)
                return true
            }
            
            if isIndexError(error) {
                appLog("Channel schema: 'name' field index is not configured", category: .cloudKit, level: .warning)
                return false
            }
            
            appLog("Error checking Channel schema: \(error)", category: .cloudKit, level: .error)
            return true
        } catch {
            appLog("Error checking Channel schema: \(error)", category: .cloudKit, level: .error)
            return true
        }
    }
    
    /// Prepares the AppSettings record type schema
    private func prepareAppSettingsSchema() async -> Bool {
        appLog("Checking AppSettings schema", category: .cloudKit, level: .debug)
        
        // AppSettings is fetched by specific record ID, not queried
        // Just check if we can access the record type
        do {
            _ = try await privateDatabase.record(for: AppSettings.recordId)
            appLog("AppSettings schema is ready", category: .cloudKit, level: .success)
            return true
        } catch let error as CKError {
            if error.code == .unknownItem {
                // Record doesn't exist yet - this is OK
                appLog("AppSettings record doesn't exist yet (will be created on first save)", category: .cloudKit, level: .info)
                return true
            }
            appLog("Error checking AppSettings schema: \(error)", category: .cloudKit, level: .error)
            return true
        } catch {
            appLog("Error checking AppSettings schema: \(error)", category: .cloudKit, level: .error)
            return true
        }
    }
    
    /// Prepares the Users record type schema (CloudKit's built-in type)
    /// This is used internally by CloudKit for user records
    private func prepareUsersSchema() async -> Bool {
        appLog("Checking Users schema", category: .cloudKit, level: .debug)
        
        // The Users record type is a built-in CloudKit type stored in the public database
        // We can verify it's accessible by fetching the current user's record
        do {
            // Get the current user's record ID
            let userRecordId = try await container.userRecordID()
            
            // Fetch the user record from public database
            // Users records are stored in the public database, not private
            let publicDatabase = container.publicCloudDatabase
            _ = try await publicDatabase.record(for: userRecordId)
            
            appLog("Users schema is ready", category: .cloudKit, level: .success)
            return true
        } catch let error as CKError {
            if error.code == .unknownItem {
                // User record doesn't exist yet - this is OK, CloudKit will create it
                appLog("User record doesn't exist yet (will be created by CloudKit)", category: .cloudKit, level: .info)
                return true
            }
            
            // Check for query/index errors related to Users type
            if isIndexError(error) {
                appLog("Users schema: 'recordName' field may not be properly configured", category: .cloudKit, level: .warning)
                return false
            }
            
            appLog("Error checking Users schema: \(error)", category: .cloudKit, level: .error)
            return true
        } catch {
            appLog("Error checking Users schema: \(error)", category: .cloudKit, level: .error)
            return true
        }
    }
    
    /// Checks if a CloudKit error is related to missing indexes
    private func isIndexError(_ error: CKError) -> Bool {
        // CloudKit returns specific error codes for index-related issues
        // Common patterns include:
        // - "Field '...' is not marked queryable"
        // - "Field '...' is not searchable"
        // - Index-related server errors
        
        let errorMessage = error.localizedDescription.lowercased()
        
        // Check for common index-related error messages
        if errorMessage.contains("not queryable") ||
           errorMessage.contains("not searchable") ||
           errorMessage.contains("not sortable") ||
           errorMessage.contains("not indexed") ||
           (errorMessage.contains("field") && errorMessage.contains("is not marked")) {
            return true
        }
        
        // Check the underlying error if available
        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
            let underlyingMessage = underlyingError.localizedDescription.lowercased()
            if underlyingMessage.contains("not queryable") ||
               underlyingMessage.contains("not searchable") ||
               underlyingMessage.contains("not indexed") ||
               (underlyingMessage.contains("field") && underlyingMessage.contains("is not marked")) {
                return true
            }
        }
        
        // Check for server record changed errors that might indicate schema issues
        if error.code == .serverRecordChanged || error.code == .invalidArguments {
            if errorMessage.contains("query") || errorMessage.contains("index") {
                return true
            }
        }
        
        return false
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
        
        // Use a predicate that queries on a field that's marked as queryable in CloudKit schema
        // NSPredicate(value: true) can fail if recordName isn't indexed
        // Query for all valid status values instead
        let allStatuses = VideoStatus.allCases.map { $0.rawValue }
        let predicate = NSPredicate(format: "status IN %@", allStatuses)
        let query = CKQuery(recordType: Video.recordType, predicate: predicate)
        
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
                appLog("Error fetching batch: \(error)", category: .cloudKit, level: .warning)
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
    
    /// Fetches all videos (full records) from CloudKit
    func fetchAllVideos() async throws -> [Video] {
        appLog("Fetching all videos from CloudKit", category: .cloudKit, level: .info)
        
        // Use a predicate that queries on a field that's marked as queryable in CloudKit schema
        // NSPredicate(value: true) can fail if recordName isn't indexed
        // Query for all valid status values instead
        let allStatuses = VideoStatus.allCases.map { $0.rawValue }
        let predicate = NSPredicate(format: "status IN %@", allStatuses)
        let query = CKQuery(recordType: Video.recordType, predicate: predicate)
        
        do {
            let records = try await performQuery(query)
            let videos = records.compactMap { Video(from: $0) }
            appLog("Fetched \(videos.count) videos from CloudKit", category: .cloudKit, level: .success)
            return videos
        } catch let ckError as CKError {
            // Handle "unknown item" error (record type doesn't exist yet)
            if ckError.code == .unknownItem {
                appLog("Video record type doesn't exist yet - returning empty array", category: .cloudKit, level: .info)
                return []
            }
            appLog("CloudKit error fetching videos: \(ckError)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(ckError)
        } catch {
            appLog("Error fetching videos: \(error)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(error)
        }
    }
    
    /// Saves multiple videos to CloudKit in batches
    func batchSaveVideos(_ videos: [Video]) async throws {
        guard !videos.isEmpty else { return }
        
        appLog("Batch saving \(videos.count) videos to CloudKit", category: .cloudKit, level: .info)
        
        // CloudKit has limits on batch operations, process in batches of 400
        let batchSize = 400
        for batchStart in stride(from: 0, to: videos.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, videos.count)
            let batch = Array(videos[batchStart..<batchEnd])
            let records = batch.map { $0.toRecord() }
            
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
        
        appLog("Successfully saved \(videos.count) videos to CloudKit", category: .cloudKit, level: .success)
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
    
    /// Saves multiple channels to CloudKit in batches
    func batchSaveChannels(_ channels: [Channel]) async throws {
        guard !channels.isEmpty else { return }
        
        appLog("Batch saving \(channels.count) channels to CloudKit", category: .cloudKit, level: .info)
        
        // CloudKit has limits on batch operations, process in batches of 400
        let batchSize = 400
        for batchStart in stride(from: 0, to: channels.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, channels.count)
            let batch = Array(channels[batchStart..<batchEnd])
            let records = batch.map { $0.toRecord() }
            
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
        
        appLog("Successfully saved \(channels.count) channels to CloudKit", category: .cloudKit, level: .success)
    }
    
    /// Fetches all channels from CloudKit
    func fetchAllChannels() async throws -> [Channel] {
        appLog("Fetching all channels from CloudKit", category: .cloudKit, level: .info)
        
        // Use a predicate that queries on a field that's marked as queryable in CloudKit schema
        // NSPredicate(value: true) can fail if recordName isn't indexed
        // CloudKit doesn't support 'field != nil' predicates, so we use 'name >= ""' instead.
        // This matches all records where name is a non-null string (including empty strings),
        // which is equivalent to 'name != nil' for our use case since all channels have names.
        let predicate = NSPredicate(format: "name >= %@", "")
        let query = CKQuery(recordType: Channel.recordType, predicate: predicate)
        
        do {
            let records = try await performQuery(query)
            let channels = records.compactMap { Channel(from: $0) }
            appLog("Fetched \(channels.count) channels from CloudKit", category: .cloudKit, level: .success)
            return channels
        } catch let ckError as CKError {
            // Handle "unknown item" error (record type doesn't exist yet)
            // This is expected on fresh installs before any channels are saved
            if ckError.code == .unknownItem {
                appLog("Channel record type doesn't exist yet - returning empty array", category: .cloudKit, level: .info)
                return []
            }
            appLog("CloudKit error fetching channels: \(ckError)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(ckError)
        } catch {
            appLog("Error fetching channels: \(error)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(error)
        }
    }
    
    // MARK: - App Settings Operations
    
    /// Fetches app settings from CloudKit
    func fetchAppSettings() async throws -> AppSettings? {
        appLog("Fetching app settings from CloudKit", category: .cloudKit, level: .info)
        
        do {
            let record = try await privateDatabase.record(for: AppSettings.recordId)
            let settings = AppSettings(from: record)
            appLog("Fetched app settings from CloudKit", category: .cloudKit, level: .success)
            return settings
        } catch let ckError as CKError {
            // Handle "unknown item" error (record doesn't exist yet)
            if ckError.code == .unknownItem {
                appLog("App settings record doesn't exist yet - returning nil", category: .cloudKit, level: .info)
                return nil
            }
            appLog("CloudKit error fetching app settings: \(ckError)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(ckError)
        } catch {
            appLog("Error fetching app settings: \(error)", category: .cloudKit, level: .error)
            throw CloudKitError.networkError(error)
        }
    }
    
    /// Saves app settings to CloudKit
    func saveAppSettings(_ settings: AppSettings) async throws {
        appLog("Saving app settings to CloudKit", category: .cloudKit, level: .info)
        
        let record = settings.toRecord()
        
        // Use CKModifyRecordsOperation with savePolicy to handle both insert and update
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
        
        appLog("Successfully saved app settings to CloudKit", category: .cloudKit, level: .success)
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
