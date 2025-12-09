//
//  YouTubeStreamExtractor.swift
//  MeTube
//
//  Service for extracting direct video stream URLs from YouTube videos
//  Note: This may conflict with YouTube ToS but is for personal use only
//

import Foundation
#if os(iOS)
import UIKit
#elseif os(tvOS)
import UIKit
#endif

/// Configuration for stream quality preferences
enum StreamQualityPreference {
    /// Always use the highest available quality
    case highest
    /// Prefer HLS adaptive streaming (adjusts to network)
    case adaptive
    /// Cap at 1080p
    case maxHD
    /// Cap at 720p
    case max720p
}

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
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let hasAudio: Bool
    
    init(url: String, quality: String, mimeType: String, qualityLabel: String?, bitrate: Int? = nil, width: Int? = nil, height: Int? = nil, hasAudio: Bool = true) {
        self.url = url
        self.quality = quality
        self.mimeType = mimeType
        self.qualityLabel = qualityLabel
        self.bitrate = bitrate
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
    }
    
    /// Quality ranking for sorting (higher is better)
    var qualityRank: Int {
        // First, use height if available (most accurate)
        if let h = height {
            return h
        }
        
        // Then try quality label
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
    
    /// Human readable description of the stream
    var description: String {
        let res = qualityLabel ?? quality
        let audio = hasAudio ? "with audio" : "video only"
        let br = bitrate.map { "\($0 / 1000)kbps" } ?? ""
        return "\(res) \(audio) \(br)".trimmingCharacters(in: .whitespaces)
    }
}

/// Service for extracting direct video stream URLs from YouTube
@MainActor
final class YouTubeStreamExtractor {
    
    /// Shared instance for reuse across video player views
    static let shared = YouTubeStreamExtractor()
    
    /// Quality preference setting - defaults to highest quality
    var qualityPreference: StreamQualityPreference = .highest
    
    /// YouTube iOS client version - may need periodic updates when YouTube changes their API.
    /// Check https://www.apkmirror.com/apk/google-inc/youtube/ for latest versions.
    /// Updated to 19.50.7 (December 2025)
    private let clientVersion = "19.50.7"
    
    /// Player signature value for YouTube API requests
    /// This value is based on the YouTube player version and may need updates when YouTube
    /// significantly updates their player. Typical range: 19000-20000+ for 2024-2025
    private let playerSignatureValue = 20200
    
    init() {
        appLog("YouTubeStreamExtractor initialized with quality preference: highest", category: .player, level: .info)
    }
    
    /// Extracts the best quality stream URL for a YouTube video
    /// - Parameter videoId: The YouTube video ID
    /// - Returns: Direct stream URL for the video (highest quality available)
    func extractStreamURL(videoId: String) async throws -> URL {
        appLog("Extracting HIGHEST QUALITY stream URL for video: \(videoId)", category: .player, level: .info)
        
        guard !videoId.isEmpty else {
            throw StreamExtractionError.invalidVideoId
        }
        
        // Try the innertube API method first (more reliable)
        do {
            let url = try await extractViaInnertubeAPI(videoId: videoId)
            appLog("Successfully extracted stream via Innertube API", category: .player, level: .success)
            return url
        } catch {
            appLog("Innertube API extraction failed: \(error)", category: .player, level: .warning)
        }
        
        // Fallback to video info endpoint
        do {
            let url = try await extractViaVideoInfo(videoId: videoId)
            appLog("Successfully extracted stream via video info", category: .player, level: .success)
            return url
        } catch {
            appLog("Video info extraction failed: \(error)", category: .player, level: .warning)
        }
        
        // Try WEB client as final fallback
        do {
            let url = try await extractViaInnertubeWebClient(videoId: videoId)
            appLog("Successfully extracted stream via Web client", category: .player, level: .success)
            return url
        } catch {
            appLog("Web client extraction failed: \(error)", category: .player, level: .warning)
        }
        
        throw StreamExtractionError.extractionFailed
    }
    
    /// Extract stream URL using YouTube's Innertube API with iOS client
    private func extractViaInnertubeAPI(videoId: String) async throws -> URL {
        return try await extractViaInnertubeAPI(videoId: videoId, clientType: "IOS")
    }
    
    /// Extract stream URL using YouTube's Innertube API with WEB client (fallback)
    private func extractViaInnertubeWebClient(videoId: String) async throws -> URL {
        return try await extractViaInnertubeAPI(videoId: videoId, clientType: "WEB")
    }
    
    /// Extract stream URL using YouTube's Innertube API with specified client type
    private func extractViaInnertubeAPI(videoId: String, clientType: String) async throws -> URL {
        appLog("extractViaInnertubeAPI starting for: \(videoId) with client: \(clientType)", category: .player, level: .debug)
        let apiURL = URL(string: "https://www.youtube.com/youtubei/v1/player")!
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        // Get device information dynamically
        let deviceModel = getDeviceModelIdentifier()
        let osVersion = UIDevice.current.systemVersion
        appLog("Device info: model=\(deviceModel), OS=\(osVersion)", category: .player, level: .debug)
        
        // Calculate a signature timestamp for player verification
        let signatureTimestamp = getPlayerSignatureValue()
        appLog("Signature timestamp: \(signatureTimestamp)", category: .player, level: .debug)
        
        // Build client context based on client type
        var clientContext: [String: Any] = [
            "clientName": clientType,
            "clientVersion": clientType == "WEB" ? "2.20231219.04.00" : clientVersion,
            "hl": "en",
            "gl": "US"
        ]
        
        // Add mobile-specific parameters for iOS client
        if clientType == "IOS" {
            clientContext["deviceMake"] = "Apple"
            clientContext["deviceModel"] = deviceModel
            clientContext["platform"] = "MOBILE"
            clientContext["osName"] = "iOS"
            clientContext["osVersion"] = osVersion
        }
        
        // Innertube client context
        let requestBody: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": clientContext
            ],
            "playbackContext": [
                "contentPlaybackContext": [
                    "signatureTimestamp": signatureTimestamp
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            appLog("Request body serialized successfully", category: .player, level: .debug)
        } catch {
            appLog("Failed to serialize request body: \(error)", category: .player, level: .error)
            throw StreamExtractionError.parsingError
        }
        
        appLog("Making network request to YouTube API", category: .player, level: .debug)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            appLog("Invalid HTTP response received", category: .player, level: .error)
            throw StreamExtractionError.networkError(NSError(domain: "HTTPError", code: 0))
        }
        
        appLog("HTTP response status: \(httpResponse.statusCode)", category: .player, level: .debug)
        
        guard httpResponse.statusCode == 200 else {
            appLog("Non-200 status code: \(httpResponse.statusCode)", category: .player, level: .error)
            throw StreamExtractionError.networkError(NSError(domain: "HTTPError", code: httpResponse.statusCode))
        }
        
        appLog("Response received, parsing player response (\(data.count) bytes)", category: .player, level: .debug)
        return try parsePlayerResponse(data)
    }
    
    /// Get the device model identifier (e.g., "iPhone14,2")
    private func getDeviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "iPhone" : identifier
    }
    
    /// Get the player signature value for YouTube API requests
    /// Returns a value based on the YouTube player version for signature verification
    private func getPlayerSignatureValue() -> Int {
        return playerSignatureValue
    }
    
    /// Extract stream URL using the video info endpoint (fallback)
    private func extractViaVideoInfo(videoId: String) async throws -> URL {
        appLog("extractViaVideoInfo starting for: \(videoId)", category: .player, level: .debug)
        
        // Try getting video info via the get_video_info-style endpoint
        guard let infoURL = URL(string: "https://www.youtube.com/watch?v=\(videoId)&pbj=1") else {
            appLog("Failed to create video info URL", category: .player, level: .error)
            throw StreamExtractionError.invalidVideoId
        }
        
        var request = URLRequest(url: infoURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        appLog("Making request to video info endpoint", category: .player, level: .debug)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            appLog("Video info response status: \(httpResponse.statusCode)", category: .player, level: .debug)
        }
        appLog("Video info response: \(data.count) bytes", category: .player, level: .debug)
        
        return try parsePlayerResponse(data)
    }
    
    /// Parse the player response to extract the best stream URL
    private func parsePlayerResponse(_ data: Data) throws -> URL {
        appLog("parsePlayerResponse called with \(data.count) bytes", category: .player, level: .debug)
        
        // Try parsing as dictionary first (direct API response)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            appLog("Parsed JSON as dictionary, keys: \(json.keys.joined(separator: ", "))", category: .player, level: .debug)
            
            // Check for playability status
            if let playabilityStatus = json["playabilityStatus"] as? [String: Any] {
                let status = playabilityStatus["status"] as? String ?? "unknown"
                let reason = playabilityStatus["reason"] as? String
                appLog("Playability status: \(status), reason: \(reason ?? "none")", category: .player, level: .debug)
                
                if status != "OK" {
                    appLog("Video not playable: \(status) - \(reason ?? "no reason")", category: .player, level: .warning)
                }
            }
            
            if let sd = json["streamingData"] as? [String: Any] {
                appLog("Found streamingData in response", category: .player, level: .debug)
                return try extractStreamFromData(sd)
            } else {
                appLog("No streamingData found in dictionary response", category: .player, level: .warning)
            }
        } else {
            appLog("Could not parse data as dictionary", category: .player, level: .debug)
        }
        
        // Try parsing as array (pbj=1 endpoint response)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            appLog("Parsed JSON as array with \(array.count) items", category: .player, level: .debug)
            for (index, item) in array.enumerated() {
                if let playerResponse = item["playerResponse"] as? [String: Any],
                   let sd = playerResponse["streamingData"] as? [String: Any] {
                    appLog("Found streamingData in array item \(index)", category: .player, level: .debug)
                    return try extractStreamFromData(sd)
                }
            }
            appLog("No streamingData found in array response", category: .player, level: .warning)
        } else {
            appLog("Could not parse data as array either", category: .player, level: .debug)
        }
        
        // Log a sample of the response for debugging
        if let responseString = String(data: data.prefix(500), encoding: .utf8) {
            appLog("Response preview: \(responseString)", category: .player, level: .debug)
        }
        
        throw StreamExtractionError.parsingError
    }
    
    /// Extract best stream URL from streaming data
    /// Prioritizes highest quality direct streams over adaptive HLS
    private func extractStreamFromData(_ streamingData: [String: Any]) throws -> URL {
        appLog("extractStreamFromData called, keys: \(streamingData.keys.joined(separator: ", "))", category: .player, level: .debug)
        appLog("Quality preference: \(qualityPreference)", category: .player, level: .debug)
        
        // Collect all available streams
        var combinedStreams: [VideoStream] = []  // Streams with both audio and video
        var adaptiveVideoStreams: [VideoStream] = []  // Video-only streams (higher quality available)
        
        // Check formats (combined audio+video streams) - these are preferred as they have audio
        if let formats = streamingData["formats"] as? [[String: Any]] {
            appLog("Found \(formats.count) combined formats", category: .player, level: .debug)
            for format in formats {
                if let stream = parseStreamFormat(format, hasAudio: true) {
                    combinedStreams.append(stream)
                    appLog("  Combined format: \(stream.description)", category: .player, level: .debug)
                }
            }
        } else {
            appLog("No 'formats' array found in streamingData", category: .player, level: .debug)
        }
        
        // Check adaptiveFormats (separate audio/video streams)
        // These often have HIGHER quality (4K, 1440p) but are video-only
        if let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] {
            appLog("Found \(adaptiveFormats.count) adaptive formats", category: .player, level: .debug)
            for format in adaptiveFormats {
                if let mimeType = format["mimeType"] as? String {
                    // Only get video streams (we'll need to handle audio separately for highest quality)
                    if mimeType.starts(with: "video/") {
                        if let stream = parseStreamFormat(format, hasAudio: false) {
                            adaptiveVideoStreams.append(stream)
                            appLog("  Adaptive video: \(stream.description)", category: .player, level: .debug)
                        }
                    }
                }
            }
        }
        
        // Sort all streams by quality (highest first)
        combinedStreams.sort { $0.qualityRank > $1.qualityRank }
        adaptiveVideoStreams.sort { $0.qualityRank > $1.qualityRank }
        
        // Log available qualities
        if let bestCombined = combinedStreams.first {
            appLog("Best combined stream: \(bestCombined.qualityLabel ?? bestCombined.quality) (\(bestCombined.qualityRank)p)", category: .player, level: .info)
        }
        if let bestAdaptive = adaptiveVideoStreams.first {
            appLog("Best adaptive stream: \(bestAdaptive.qualityLabel ?? bestAdaptive.quality) (\(bestAdaptive.qualityRank)p)", category: .player, level: .info)
        }
        
        // For HIGHEST quality preference:
        // 1. First try to use the highest quality combined stream (has audio)
        // 2. Only use HLS if no direct streams available (HLS is adaptive, not always highest quality)
        
        // Determine what quality cap to apply
        let maxQuality: Int
        switch qualityPreference {
        case .highest:
            maxQuality = Int.max  // No cap - use highest available
        case .adaptive:
            maxQuality = Int.max  // Will prefer HLS below
        case .maxHD:
            maxQuality = 1080
        case .max720p:
            maxQuality = 720
        }
        
        // Filter combined streams by quality cap and select the best one
        let eligibleCombinedStreams = combinedStreams.filter { $0.qualityRank <= maxQuality }
        
        // For highest quality preference, use direct streams first (they provide the best quality)
        if qualityPreference == .highest {
            // Prefer the highest quality combined stream
            if let bestCombined = eligibleCombinedStreams.first,
               let url = URL(string: bestCombined.url) {
                appLog("✓ Selected HIGHEST QUALITY combined stream: \(bestCombined.qualityLabel ?? bestCombined.quality)", category: .player, level: .success)
                return url
            }
            
            // If no combined stream, check if adaptive has higher quality
            // Note: Adaptive streams are video-only, so playback may not have audio
            // For now, we'll skip adaptive-only and fall back to HLS which handles audio properly
        }
        
        // For adaptive preference or as fallback, use HLS
        if let hlsManifestUrl = streamingData["hlsManifestUrl"] as? String,
           let url = URL(string: hlsManifestUrl) {
            if qualityPreference == .adaptive {
                appLog("✓ Selected HLS adaptive stream (as preferred)", category: .player, level: .success)
            } else {
                appLog("✓ Selected HLS stream as fallback", category: .player, level: .success)
            }
            return url
        }
        
        // Final fallback: any available combined stream
        if let bestStream = eligibleCombinedStreams.first ?? combinedStreams.first,
           let url = URL(string: bestStream.url) {
            appLog("✓ Selected stream (fallback): \(bestStream.qualityLabel ?? bestStream.quality)", category: .player, level: .success)
            return url
        }
        
        appLog("No playable streams found", category: .player, level: .error)
        throw StreamExtractionError.noStreamAvailable
    }
    
    /// Parse a single format entry into a VideoStream
    private func parseStreamFormat(_ format: [String: Any], hasAudio: Bool = true) -> VideoStream? {
        guard let url = format["url"] as? String,
              let mimeType = format["mimeType"] as? String,
              let quality = format["quality"] as? String else {
            return nil
        }
        
        let qualityLabel = format["qualityLabel"] as? String
        let bitrate = format["bitrate"] as? Int
        let width = format["width"] as? Int
        let height = format["height"] as? Int
        
        return VideoStream(
            url: url,
            quality: quality,
            mimeType: mimeType,
            qualityLabel: qualityLabel,
            bitrate: bitrate,
            width: width,
            height: height,
            hasAudio: hasAudio
        )
    }
}
