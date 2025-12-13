//
//  MeTubeAPIService.swift
//  MeTube
//
//  Client for the MeTube backend API documented in API.md
//

import Foundation

// MARK: - Configuration

enum MeTubeAPIConfig {
    static let baseURL = URL(string: "https://metube.brrai.nz")!
    static let defaultVideoLimit = 500
    static let maxVideoLimit = 500
}

// MARK: - Errors

enum MeTubeAPIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "Server error (\(code))"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Models

struct MeTubeChannelsResponse: Codable {
    let channels: [MeTubeChannelDTO]
}

struct MeTubeChannelDTO: Codable {
    let channelId: String
    let title: String?
    let thumbnailUrl: String?
}

struct MeTubeVideosQueryRequest: Codable {
    let afterSeq: Int
    let limit: Int?
}

struct MeTubeVideosQueryResponse: Codable {
    let videos: [MeTubeVideoDTO]
    let maxSeqReturned: Int
}

struct MeTubeVideoDTO: Codable {
    let seq: Int
    let videoId: String
    let channelId: String
    let publishedAt: Date
    let title: String
    let url: URL
    let durationSeconds: Int?
}

// MARK: - Service

final class MeTubeAPIService: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = MeTubeAPIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        appLog("MeTubeAPIService initialized with base URL: \(baseURL.absoluteString)", category: .feed, level: .info)
    }

    func fetchAllChannels() async throws -> [MeTubeChannelDTO] {
        var request = URLRequest(url: baseURL.appending(path: "/api/channels"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await data(for: request)

        do {
            return try decoder().decode(MeTubeChannelsResponse.self, from: data).channels
        } catch {
            throw MeTubeAPIError.decodingError(error)
        }
    }

    func queryVideos(afterSeq: Int, limit: Int? = nil) async throws -> MeTubeVideosQueryResponse {
        var request = URLRequest(url: baseURL.appending(path: "/api/videos/query"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let normalizedLimit: Int? = {
            guard let limit else { return nil }
            return max(1, min(limit, MeTubeAPIConfig.maxVideoLimit))
        }()

        let body = MeTubeVideosQueryRequest(afterSeq: max(0, afterSeq), limit: normalizedLimit)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await data(for: request)

        do {
            return try decoder().decode(MeTubeVideosQueryResponse.self, from: data)
        } catch {
            throw MeTubeAPIError.decodingError(error)
        }
    }

    // MARK: - Helpers

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MeTubeAPIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw MeTubeAPIError.httpError(http.statusCode)
            }
            return (data, http)
        } catch let error as MeTubeAPIError {
            throw error
        } catch {
            throw MeTubeAPIError.networkError(error)
        }
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = ISO8601DateFormatter.metube.decode(value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let metube: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func decode(_ value: String) -> Date? {
        if let date = date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}
