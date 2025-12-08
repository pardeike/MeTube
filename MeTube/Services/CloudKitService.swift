//
//  CloudKitService.swift
//  MeTube
//
//  Service for CloudKit operations (AppSettings storage only)
//  Note: Video and Channel data is now stored locally in SwiftData and synced from hub server.
//  Only watch status (StatusEntity) is synced via CloudKit through StatusSyncManager.
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

/// Service for managing CloudKit operations
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
        var allReady: Bool {
            return videoSchemaReady && channelSchemaReady && appSettingsSchemaReady && usersSchemaReady
        }
    }
    
    /// Prepares the CloudKit schema by verifying required record types exist.
    ///
    /// - Returns: A result indicating which schemas are ready and any errors encountered
    func prepareSchema() async -> SchemaPreparationResult {
        appLog("Preparing CloudKit schema", category: .cloudKit, level: .info)
        
        var errors: [String] = []
        
        // Video and Channel schemas are no longer used (stored in SwiftData, not CloudKit)
        let videoReady = true
        let channelReady = true
        
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
    private func prepareUsersSchema() async -> Bool {
        appLog("Checking Users schema", category: .cloudKit, level: .debug)
        
        // The Users record type is a built-in CloudKit type stored in the public database
        do {
            // Get the current user's record ID
            let userRecordId = try await container.userRecordID()
            
            // Fetch the user record from public database
            let publicDatabase = container.publicCloudDatabase
            _ = try await publicDatabase.record(for: userRecordId)
            
            appLog("Users schema is ready", category: .cloudKit, level: .success)
            return true
        } catch let error as CKError {
            if error.code == .unknownItem {
                // User record doesn't exist yet - this is OK
                appLog("User record doesn't exist yet (will be created by CloudKit)", category: .cloudKit, level: .info)
                return true
            }
            
            // Check for query/index errors
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
        let errorMessage = error.localizedDescription.lowercased()
        return errorMessage.contains("not marked queryable") ||
               errorMessage.contains("not searchable") ||
               errorMessage.contains("index") ||
               error.code == .invalidArguments
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
}
