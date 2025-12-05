//
//  YouTubeService.swift
//  MeTube
//
//  Service for interacting with YouTube Data API v3
//

import Foundation

enum YouTubeAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case quotaExceeded
    case unauthorized
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from YouTube API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .quotaExceeded:
            return "YouTube API quota exceeded. Try again tomorrow."
        case .unauthorized:
            return "Authentication required. Please sign in again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/// Service for interacting with YouTube Data API v3
class YouTubeService {
    private let baseURL = "https://www.googleapis.com/youtube/v3"
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Subscriptions
    
    /// Fetches all subscribed channels for the authenticated user
    func fetchSubscriptions(accessToken: String) async throws -> [Channel] {
        var allChannels: [Channel] = []
        var nextPageToken: String? = nil
        
        repeat {
            let response = try await fetchSubscriptionsPage(accessToken: accessToken, pageToken: nextPageToken)
            
            for item in response.items {
                let channel = Channel(
                    id: item.snippet.resourceId.channelId,
                    name: item.snippet.title,
                    thumbnailURL: item.snippet.thumbnails.bestURL,
                    description: item.snippet.description
                )
                allChannels.append(channel)
            }
            
            nextPageToken = response.nextPageToken
        } while nextPageToken != nil
        
        // Fetch uploads playlist IDs for all channels
        let channelIds = allChannels.map { $0.id }
        let uploadsPlaylistIds = try await fetchUploadsPlaylistIds(channelIds: channelIds, accessToken: accessToken)
        
        // Update channels with uploads playlist IDs
        for i in 0..<allChannels.count {
            if let playlistId = uploadsPlaylistIds[allChannels[i].id] {
                allChannels[i].uploadsPlaylistId = playlistId
            }
        }
        
        return allChannels
    }
    
    private func fetchSubscriptionsPage(accessToken: String, pageToken: String?) async throws -> SubscriptionListResponse {
        var urlComponents = URLComponents(string: "\(baseURL)/subscriptions")!
        urlComponents.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50")
        ]
        
        if let pageToken = pageToken {
            urlComponents.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        
        guard let url = urlComponents.url else {
            throw YouTubeAPIError.invalidURL
        }
        
        return try await performRequest(url: url, accessToken: accessToken)
    }
    
    private func fetchUploadsPlaylistIds(channelIds: [String], accessToken: String) async throws -> [String: String] {
        var result: [String: String] = [:]
        
        // Process in batches of 50 (API limit)
        for batchStart in stride(from: 0, to: channelIds.count, by: 50) {
            let batchEnd = min(batchStart + 50, channelIds.count)
            let batch = Array(channelIds[batchStart..<batchEnd])
            
            var urlComponents = URLComponents(string: "\(baseURL)/channels")!
            urlComponents.queryItems = [
                URLQueryItem(name: "part", value: "contentDetails"),
                URLQueryItem(name: "id", value: batch.joined(separator: ",")),
                URLQueryItem(name: "maxResults", value: "50")
            ]
            
            guard let url = urlComponents.url else {
                throw YouTubeAPIError.invalidURL
            }
            
            let response: ChannelListResponse = try await performRequest(url: url, accessToken: accessToken)
            
            for item in response.items {
                if let uploadsPlaylistId = item.contentDetails?.relatedPlaylists.uploads {
                    result[item.id] = uploadsPlaylistId
                }
            }
        }
        
        return result
    }
    
    // MARK: - Videos
    
    /// Fetches recent videos from a channel's uploads playlist
    func fetchChannelVideos(channel: Channel, accessToken: String, maxResults: Int = 20) async throws -> [Video] {
        guard let uploadsPlaylistId = channel.uploadsPlaylistId else {
            return []
        }
        
        // Fetch playlist items
        let playlistItems = try await fetchPlaylistItems(playlistId: uploadsPlaylistId, accessToken: accessToken, maxResults: maxResults)
        
        // Get video IDs for duration check
        let videoIds = playlistItems.map { $0.contentDetails.videoId }
        
        // Fetch video details (including duration)
        let videoDurations = try await fetchVideoDurations(videoIds: videoIds, accessToken: accessToken)
        
        // Create Video objects, filtering out Shorts
        var videos: [Video] = []
        
        for item in playlistItems {
            let videoId = item.contentDetails.videoId
            let duration = videoDurations[videoId] ?? 0
            
            // Skip shorts (videos under 60 seconds)
            if duration < 60 {
                continue
            }
            
            // Parse publish date
            let publishDate = parseISO8601Date(item.snippet.publishedAt) ?? Date()
            
            let video = Video(
                id: videoId,
                title: item.snippet.title,
                channelId: channel.id,
                channelName: channel.name,
                publishedDate: publishDate,
                duration: duration,
                thumbnailURL: item.snippet.thumbnails.bestURL,
                description: item.snippet.description
            )
            
            videos.append(video)
        }
        
        return videos
    }
    
    private func fetchPlaylistItems(playlistId: String, accessToken: String, maxResults: Int) async throws -> [PlaylistItem] {
        var urlComponents = URLComponents(string: "\(baseURL)/playlistItems")!
        urlComponents.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "maxResults", value: "\(min(maxResults, 50))")
        ]
        
        guard let url = urlComponents.url else {
            throw YouTubeAPIError.invalidURL
        }
        
        let response: PlaylistItemListResponse = try await performRequest(url: url, accessToken: accessToken)
        return response.items
    }
    
    private func fetchVideoDurations(videoIds: [String], accessToken: String) async throws -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        
        // Process in batches of 50 (API limit)
        for batchStart in stride(from: 0, to: videoIds.count, by: 50) {
            let batchEnd = min(batchStart + 50, videoIds.count)
            let batch = Array(videoIds[batchStart..<batchEnd])
            
            var urlComponents = URLComponents(string: "\(baseURL)/videos")!
            urlComponents.queryItems = [
                URLQueryItem(name: "part", value: "contentDetails"),
                URLQueryItem(name: "id", value: batch.joined(separator: ",")),
                URLQueryItem(name: "maxResults", value: "50")
            ]
            
            guard let url = urlComponents.url else {
                throw YouTubeAPIError.invalidURL
            }
            
            let response: VideoListResponse = try await performRequest(url: url, accessToken: accessToken)
            
            for item in response.items {
                if let durationString = item.contentDetails?.duration {
                    result[item.id] = parseISO8601Duration(durationString)
                }
            }
        }
        
        return result
    }
    
    // MARK: - Helper Methods
    
    private func performRequest<T: Decodable>(url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw YouTubeAPIError.decodingError(error)
            }
        case 401:
            throw YouTubeAPIError.unauthorized
        case 403:
            // Check if it's a quota exceeded error
            throw YouTubeAPIError.quotaExceeded
        default:
            throw YouTubeAPIError.httpError(httpResponse.statusCode)
        }
    }
    
    /// Parses an ISO 8601 date string to a Date object
    private func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    /// Parses an ISO 8601 duration string to TimeInterval (seconds)
    /// Format: PT[hours]H[minutes]M[seconds]S
    /// Examples:
    /// - "PT1H2M10S" = 1 hour, 2 minutes, 10 seconds = 3730 seconds
    /// - "PT5M30S" = 5 minutes, 30 seconds = 330 seconds
    /// - "PT45S" = 45 seconds
    private func parseISO8601Duration(_ durationString: String) -> TimeInterval {
        var duration: TimeInterval = 0
        // Regex captures optional hours (H), minutes (M), and seconds (S) groups
        let pattern = "PT(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: durationString, options: [], range: NSRange(durationString.startIndex..., in: durationString)) else {
            return 0
        }
        
        if let hoursRange = Range(match.range(at: 1), in: durationString),
           let hours = Double(durationString[hoursRange]) {
            duration += hours * 3600
        }
        
        if let minutesRange = Range(match.range(at: 2), in: durationString),
           let minutes = Double(durationString[minutesRange]) {
            duration += minutes * 60
        }
        
        if let secondsRange = Range(match.range(at: 3), in: durationString),
           let seconds = Double(durationString[secondsRange]) {
            duration += seconds
        }
        
        return duration
    }
}
