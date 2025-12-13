//
//  CloudKitService.swift
//  MeTube
//
//  CloudKit utilities used for syncing video state (watched/skipped/playhead).
//

import CloudKit
import Foundation

enum CloudKitError: LocalizedError {
    case notAuthenticated
    case networkError(Error)
    case unknownError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "iCloud account not available. Please sign in to iCloud."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

enum CloudKitConfig {
    static let containerIdentifier = "iCloud.com.metube.app"
}

final class CloudKitService {
    private let container: CKContainer

    init(containerIdentifier: String = CloudKitConfig.containerIdentifier) {
        self.container = CKContainer(identifier: containerIdentifier)
        appLog("Initializing CloudKitService with container: \(containerIdentifier)", category: .cloudKit, level: .info)
    }

    /// Checks if iCloud is available for the current user.
    func checkiCloudStatus() async -> Bool {
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
}

