//
//  YouTubeStreamExtractor.swift
//  MeTube
//
//  Service for extracting direct video stream URLs from YouTube videos
//  Note: This may conflict with YouTube ToS but is for personal use only
//

import Foundation

/// Error types for stream extraction
enum StreamExtractionError: LocalizedError {
    case invalidVideoId
    case extractionFailed
    case noStreamAvailable
    case networkError(Error)
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidVideoId:
            return "Invalid video ID"
        case .extractionFailed:
            return "Failed to extract stream URL"
        case .noStreamAvailable:
            return "No playable stream found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError:
            return "Failed to parse video info"
        }
    }
}

/// Represents an extracted video stream
struct VideoStream: Codable {
    let url: String
    let quality: String
    let mimeType: String
    let qualityLabel: String?
    
    /// Quality ranking for sorting (higher is better)
    var qualityRank: Int {
        if let label = qualityLabel {
            if label.contains("2160") || label.contains("4K") { return 2160 }
            if label.contains("1440") { return 1440 }
            if label.contains("1080") { return 1080 }
            if label.contains("720") { return 720 }
            if label.contains("480") { return 480 }
            if label.contains("360") { return 360 }
            if label.contains("240") { return 240 }
            if label.contains("144") { return 144 }
        }
        // Fallback based on quality string
        switch quality {
        case "hd2160": return 2160
        case "hd1440": return 1440
        case "hd1080": return 1080
        case "hd720": return 720
        case "large": return 480
        case "medium": return 360
        case "small": return 240
        case "tiny": return 144
        default: return 0
        }
    }
}

/// Service for extracting direct video stream URLs from YouTube
@MainActor
final class YouTubeStreamExtractor {
    
    init() {
        appLog("YouTubeStreamExtractor initialized", category: .player, level: .info)
    }
    
    /// Extracts the best quality stream URL for a YouTube video
    /// - Parameter videoId: The YouTube video ID
    /// - Returns: Direct stream URL for the video
    func extractStreamURL(videoId: String) async throws -> URL {
        appLog("Extracting stream URL for video: \(videoId)", category: .player, level: .info)
        
        guard !videoId.isEmpty else {
            throw StreamExtractionError.invalidVideoId
        }
        
        // Try the innertube API method first (more reliable)
        if let url = try? await extractViaInnertubeAPI(videoId: videoId) {
            appLog("Successfully extracted stream via Innertube API", category: .player, level: .success)
            return url
        }
        
        // Fallback to video info endpoint
        if let url = try? await extractViaVideoInfo(videoId: videoId) {
            appLog("Successfully extracted stream via video info", category: .player, level: .success)
            return url
        }
        
        throw StreamExtractionError.extractionFailed
    }
    
    /// Extract stream URL using YouTube's Innertube API
    private func extractViaInnertubeAPI(videoId: String) async throws -> URL {
        let apiURL = URL(string: "https://www.youtube.com/youtubei/v1/player")!
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        // Innertube client context for iOS
        let requestBody: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": [
                    "clientName": "IOS",
                    "clientVersion": "19.29.1",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "platform": "MOBILE",
                    "osName": "iOS",
                    "osVersion": "17.5.1.21F90",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "playbackContext": [
                "contentPlaybackContext": [
                    "signatureTimestamp": "19999"
                ]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StreamExtractionError.networkError(NSError(domain: "HTTPError", code: (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        
        return try parsePlayerResponse(data)
    }
    
    /// Extract stream URL using the video info endpoint (fallback)
    private func extractViaVideoInfo(videoId: String) async throws -> URL {
        // Try getting video info via the get_video_info-style endpoint
        guard let infoURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)&pbj=1") else {
            throw StreamExtractionError.invalidVideoId
        }
        
        var request = URLRequest(url: infoURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        return try parsePlayerResponse(data)
    }
    
    /// Parse the player response to extract the best stream URL
    private func parsePlayerResponse(_ data: Data) throws -> URL {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamExtractionError.parsingError
        }
        
        // Navigate through the response structure
        var streamingData: [String: Any]?
        
        // Direct response format
        if let sd = json["streamingData"] as? [String: Any] {
            streamingData = sd
        }
        // Array response format (pbj=1 endpoint)
        else if let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for item in array {
                if let playerResponse = item["playerResponse"] as? [String: Any],
                   let sd = playerResponse["streamingData"] as? [String: Any] {
                    streamingData = sd
                    break
                }
            }
        }
        
        guard let streamingData = streamingData else {
            throw StreamExtractionError.noStreamAvailable
        }
        
        // Collect all available streams
        var streams: [VideoStream] = []
        
        // Check formats (combined audio+video streams)
        if let formats = streamingData["formats"] as? [[String: Any]] {
            for format in formats {
                if let stream = parseStreamFormat(format) {
                    streams.append(stream)
                }
            }
        }
        
        // Check adaptiveFormats (separate audio/video streams)
        // We prefer combined formats, but adaptive can be used as fallback
        if streams.isEmpty, let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] {
            for format in adaptiveFormats {
                // Only get video streams with audio or video-only streams
                if let mimeType = format["mimeType"] as? String,
                   mimeType.starts(with: "video/") {
                    if let stream = parseStreamFormat(format) {
                        streams.append(stream)
                    }
                }
            }
        }
        
        // Also check for HLS manifest URL (best for iOS)
        if let hlsManifestUrl = streamingData["hlsManifestUrl"] as? String,
           let url = URL(string: hlsManifestUrl) {
            appLog("Found HLS manifest URL", category: .player, level: .success)
            return url
        }
        
        // Sort streams by quality and pick the best one
        streams.sort { $0.qualityRank > $1.qualityRank }
        
        guard let bestStream = streams.first,
              let url = URL(string: bestStream.url) else {
            throw StreamExtractionError.noStreamAvailable
        }
        
        appLog("Selected stream: \(bestStream.quality) (\(bestStream.qualityLabel ?? "unknown"))", category: .player, level: .info)
        return url
    }
    
    /// Parse a single format entry into a VideoStream
    private func parseStreamFormat(_ format: [String: Any]) -> VideoStream? {
        guard let url = format["url"] as? String,
              let mimeType = format["mimeType"] as? String,
              let quality = format["quality"] as? String else {
            return nil
        }
        
        let qualityLabel = format["qualityLabel"] as? String
        
        return VideoStream(
            url: url,
            quality: quality,
            mimeType: mimeType,
            qualityLabel: qualityLabel
        )
    }
}
