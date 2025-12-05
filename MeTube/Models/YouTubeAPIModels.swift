//
//  YouTubeAPIModels.swift
//  MeTube
//
//  Models for YouTube Data API v3 responses
//

import Foundation

// MARK: - Subscriptions Response

struct SubscriptionListResponse: Codable {
    let items: [SubscriptionItem]
    let nextPageToken: String?
    let pageInfo: PageInfo
}

struct SubscriptionItem: Codable {
    let snippet: SubscriptionSnippet
}

struct SubscriptionSnippet: Codable {
    let title: String
    let description: String
    let resourceId: ResourceId
    let thumbnails: Thumbnails
}

struct ResourceId: Codable {
    let channelId: String
}

// MARK: - Channel Response

struct ChannelListResponse: Codable {
    let items: [ChannelItem]
}

struct ChannelItem: Codable {
    let id: String
    let contentDetails: ChannelContentDetails?
}

struct ChannelContentDetails: Codable {
    let relatedPlaylists: RelatedPlaylists
}

struct RelatedPlaylists: Codable {
    let uploads: String
}

// MARK: - Playlist Items Response

struct PlaylistItemListResponse: Codable {
    let items: [PlaylistItem]
    let nextPageToken: String?
    let pageInfo: PageInfo
}

struct PlaylistItem: Codable {
    let snippet: PlaylistItemSnippet
    let contentDetails: PlaylistItemContentDetails
}

struct PlaylistItemSnippet: Codable {
    let title: String
    let description: String
    let channelTitle: String
    let channelId: String
    let publishedAt: String
    let thumbnails: Thumbnails
    let resourceId: VideoResourceId
}

struct VideoResourceId: Codable {
    let videoId: String
}

struct PlaylistItemContentDetails: Codable {
    let videoId: String
    let videoPublishedAt: String?
}

// MARK: - Videos Response (for duration)

struct VideoListResponse: Codable {
    let items: [VideoItem]
}

struct VideoItem: Codable {
    let id: String
    let contentDetails: VideoContentDetails?
    let snippet: VideoSnippet?
}

struct VideoContentDetails: Codable {
    let duration: String  // ISO 8601 duration format (e.g., "PT1H2M10S")
}

struct VideoSnippet: Codable {
    let title: String
    let description: String
    let channelTitle: String
    let channelId: String
    let publishedAt: String
    let thumbnails: Thumbnails
}

// MARK: - Common Types

struct Thumbnails: Codable {
    let `default`: ThumbnailInfo?
    let medium: ThumbnailInfo?
    let high: ThumbnailInfo?
    let standard: ThumbnailInfo?
    let maxres: ThumbnailInfo?
    
    /// Returns the best available thumbnail URL
    var bestURL: URL? {
        if let maxres = maxres?.url {
            return URL(string: maxres)
        } else if let high = high?.url {
            return URL(string: high)
        } else if let medium = medium?.url {
            return URL(string: medium)
        } else if let standard = standard?.url {
            return URL(string: standard)
        } else if let defaultThumb = `default`?.url {
            return URL(string: defaultThumb)
        }
        return nil
    }
}

struct ThumbnailInfo: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

struct PageInfo: Codable {
    let totalResults: Int
    let resultsPerPage: Int
}
