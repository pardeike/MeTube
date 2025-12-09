//
//  HubServerService.swift
//  MeTube
//
//  Service for communicating with the MeTube Hub Server
//  See SERVER_INTEGRATION.md for API documentation
//

import Foundation

// MARK: - Hub Configuration

/// Configuration for the MeTube Hub Server
enum HubConfig {
    #if DEBUG
    // For development/testing - can point to localhost
    static let baseURL = "https://metube.pardeike.net"
    #else
    static let baseURL = "https://metube.pardeike.net"
    #endif
    
    /// User ID key in UserDefaults
    static let userIdKey = "hubUserId"
    
    /// Retry configuration
    static let maxRetries = 3
    static let baseRetryDelay: TimeInterval = 1.0 // Base delay in seconds for exponential backoff
}

// MARK: - Hub Errors

enum HubError: LocalizedError, Equatable {
    case serverUnhealthy
    case registrationFailed
    case reconciliationFailed
    case fetchFailed
    case networkError(Error)
    case decodingError(Error)
    case invalidResponse
    case userNotFound
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .serverUnhealthy:
            return "Hub server is unavailable. Please try again later."
        case .registrationFailed:
            return "Could not register your channels. Please check your connection."
        case .reconciliationFailed:
            return "Could not check for new videos. Please try again."
        case .fetchFailed:
            return "Could not fetch videos. Pull to refresh to try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Data format error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Unexpected server response. Please try again."
        case .userNotFound:
            return "User not found on server. Please re-sync your subscriptions."
        case .invalidURL:
            return "Invalid server URL"
        }
    }
    
    // Implement Equatable conformance
    static func == (lhs: HubError, rhs: HubError) -> Bool {
        switch (lhs, rhs) {
        case (.serverUnhealthy, .serverUnhealthy),
             (.registrationFailed, .registrationFailed),
             (.reconciliationFailed, .reconciliationFailed),
             (.fetchFailed, .fetchFailed),
             (.invalidResponse, .invalidResponse),
             (.userNotFound, .userNotFound),
             (.invalidURL, .invalidURL):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)),
             (.decodingError(let lhsError), .decodingError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Response Models

struct HealthResponse: Codable {
    let status: String
    let timestamp: Date
    let stats: Stats
    
    struct Stats: Codable {
        let channels: Int
        let users: Int
        let videos: Int
    }
}

struct RegisterChannelsRequest: Codable {
    let channelIds: [String]
}

struct RegisterChannelsResponse: Codable {
    let message: String
}

struct ReconcileResponse: Codable {
    let message: String
    let newVideosCount: Int
}

struct FeedResponse: Codable {
    let videos: [VideoDTO]
    let nextCursor: String?
    let nextPageToken: String? // Deprecated, but kept for compatibility
}

struct VideoDTO: Codable {
    let videoId: String
    let channelId: String
    let publishedAt: Date
    let title: String?
    let description: String?
    let thumbnailUrl: String?
    let duration: TimeInterval?
    
    enum CodingKeys: String, CodingKey {
        case videoId, channelId, publishedAt, title, description, thumbnailUrl, duration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try container.decode(String.self, forKey: .videoId)
        channelId = try container.decode(String.self, forKey: .channelId)
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        
        // Duration comes as TimeSpan string "00:04:13" or as TimeInterval
        if let durationDouble = try? container.decodeIfPresent(Double.self, forKey: .duration) {
            duration = durationDouble
        } else if let durationStr = try container.decodeIfPresent(String.self, forKey: .duration) {
            duration = Self.parseTimeSpan(durationStr)
        } else {
            duration = nil
        }
    }
    
    /// Parses a TimeSpan string to TimeInterval
    /// Format: "HH:MM:SS" or "MM:SS"
    private static func parseTimeSpan(_ timeSpan: String) -> TimeInterval? {
        let components = timeSpan.split(separator: ":")
        guard components.count >= 2 else { return nil }
        
        if components.count == 3 {
            // HH:MM:SS
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        } else {
            // MM:SS
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1]) else { return nil }
            return minutes * 60 + seconds
        }
    }
}

// MARK: - Hub Server Service

/// Service for communicating with the MeTube Hub Server
/// This class is thread-safe as it only uses immutable properties and URLSession (which is thread-safe)
final class HubServerService: Sendable {
    private let baseURL: String
    private let session: URLSession
    
    init(baseURL: String = HubConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        appLog("HubServerService initialized with base URL: \(baseURL)", category: .feed, level: .info)
    }
    
    // MARK: - User ID Management
    
    /// Gets or creates a stable user ID for this device
    /// The ID is stored in UserDefaults and persists across app launches
    static func getUserId() -> String {
        if let saved = UserDefaults.standard.string(forKey: HubConfig.userIdKey) {
            return saved
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: HubConfig.userIdKey)
        appLog("Generated new hub user ID: \(newId)", category: .feed, level: .info)
        return newId
    }
    
    // MARK: - Health Check
    
    /// Checks if the hub server is healthy and accessible
    func checkHealth() async throws -> HealthResponse {
        appLog("Checking hub server health", category: .feed, level: .info)
        
        guard let url = URL(string: "\(baseURL)/health") else {
            throw HubError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            appLog("Hub server health check failed", category: .feed, level: .error)
            throw HubError.serverUnhealthy
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let health = try decoder.decode(HealthResponse.self, from: data)
        
        appLog("Hub server is healthy - \(health.stats.channels) channels, \(health.stats.users) users, \(health.stats.videos) videos", category: .feed, level: .success)
        return health
    }
    
    // MARK: - Channel Registration
    
    /// Registers the user's subscribed channels with the hub server
    /// This tells the server which channels to track for this user
    func registerChannels(userId: String, channelIds: [String]) async throws {
        appLog("Registering \(channelIds.count) channels for user \(userId)", category: .feed, level: .info)
        
        // Use retry logic for channel registration to handle network timeouts
        try await fetchWithRetry { [self] in
            guard let url = URL(string: "\(baseURL)/api/users/\(userId)/channels") else {
                throw HubError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = RegisterChannelsRequest(channelIds: channelIds)
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                appLog("Channel registration failed", category: .feed, level: .error)
                throw HubError.registrationFailed
            }
            
            let result = try JSONDecoder().decode(RegisterChannelsResponse.self, from: data)
            appLog("Channel registration successful: \(result.message)", category: .feed, level: .success)
        }
    }
    
    // MARK: - Reconciliation
    
    /// Triggers on-demand reconciliation to check for new videos
    /// This should be called before fetching the feed to ensure fresh data
    /// - Parameter userId: The user's unique ID
    /// - Returns: Number of new videos found during reconciliation
    func reconcileChannels(userId: String) async throws -> Int {
        appLog("Triggering reconciliation for user \(userId)", category: .feed, level: .info)
        
        return try await fetchWithRetry { [self] in
            guard let url = URL(string: "\(baseURL)/api/users/\(userId)/reconcile") else {
                throw HubError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HubError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                let result = try JSONDecoder().decode(ReconcileResponse.self, from: data)
                appLog("Reconciliation completed: \(result.newVideosCount) new videos found", category: .feed, level: .success)
                return result.newVideosCount
            case 404:
                throw HubError.userNotFound
            default:
                appLog("Reconciliation failed with status code \(httpResponse.statusCode)", category: .feed, level: .error)
                throw HubError.reconciliationFailed
            }
        }
    }
    
    // MARK: - Feed Fetching
    
    /// Fetches the aggregated video feed for a user
    /// - Parameters:
    ///   - userId: The user's unique ID
    ///   - since: Optional timestamp to fetch only videos published after this date
    ///   - cursor: Optional pagination cursor for fetching subsequent pages
    ///   - limit: Maximum number of videos to return (default: 50)
    func fetchFeed(userId: String, since: Date? = nil, cursor: String? = nil, limit: Int = 50) async throws -> FeedResponse {
        appLog("Fetching feed for user \(userId)", category: .feed, level: .info, context: [
            "since": since?.description ?? "none",
            "cursor": cursor ?? "none",
            "limit": limit
        ])
        
        var components = URLComponents(string: "\(baseURL)/api/users/\(userId)/feed")
        guard components != nil else {
            throw HubError.invalidURL
        }
        
        var queryItems: [URLQueryItem] = []
        
        if let since = since {
            let iso8601 = ISO8601DateFormatter().string(from: since)
            queryItems.append(URLQueryItem(name: "since", value: iso8601))
        }
        
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw HubError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HubError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let feed = try decoder.decode(FeedResponse.self, from: data)
            appLog("Fetched \(feed.videos.count) videos from feed", category: .feed, level: .success)
            return feed
        case 404:
            throw HubError.userNotFound
        default:
            appLog("Feed fetch failed with status code \(httpResponse.statusCode)", category: .feed, level: .error)
            throw HubError.fetchFailed
        }
    }
    
    // MARK: - Retry Logic
    
    /// Executes an operation with retry logic and exponential backoff
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts (defaults to HubConfig.maxRetries)
    ///   - operation: The async operation to retry
    func fetchWithRetry<T>(
        maxRetries: Int = HubConfig.maxRetries,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt < maxRetries - 1 {
                    let delay = HubConfig.baseRetryDelay * pow(2.0, Double(attempt)) // 1s, 2s, 4s
                    appLog("Retry attempt \(attempt + 1) after \(delay)s delay", category: .feed, level: .warning)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? HubError.fetchFailed
    }
}
