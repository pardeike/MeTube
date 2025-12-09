//
//  SharedTypes.swift
//  MeTube
//
//  Shared type definitions used across iOS and tvOS platforms
//

import Foundation

/// Filter options for channel list
/// Used in both iOS ChannelsView and tvOS TVChannelsView
enum ChannelFilter: String, CaseIterable {
    case all = "All Channels"
    case withUnseenVideos = "With Unseen Videos"
}

/// Filter options for channel videos
/// Used in both iOS ChannelDetailView and tvOS TVChannelDetailView
enum ChannelVideoFilter: String, CaseIterable {
    case all = "All Videos"
    case unwatched = "Unwatched"
    case skipped = "Skipped"
}

/// Tracks the state of video loading and playback
/// Used in both iOS VideoPlayerView and tvOS TVVideoPlayerView
enum PlayerLoadingState: Equatable {
    case idle
    case extracting
    case loading
    case ready
    case failed(String)
    
    static func == (lhs: PlayerLoadingState, rhs: PlayerLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.extracting, .extracting), (.loading, .loading), (.ready, .ready):
            return true
        case (.failed(let l), .failed(let r)):
            return l == r
        default:
            return false
        }
    }
}
