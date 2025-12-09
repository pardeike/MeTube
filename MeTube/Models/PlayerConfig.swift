//
//  PlayerConfig.swift
//  MeTube
//
//  Global configuration for video player selection
//

import Foundation

/// Configuration for video playback
/// This is the global toggle to switch between player implementations
enum PlayerConfig {
    // MARK: - Player Selection Toggle
    
    /// Set to `true` to use the direct stream player (AVPlayer with extracted URLs)
    /// Set to `false` to use the YouTube SDK player (WKWebView with IFrame API)
    ///
    /// **Direct Player (default: true)**
    /// - Uses AVPlayer with extracted stream URLs
    /// - Better AirPlay support
    /// - No YouTube UI/branding
    /// - May break if YouTube changes extraction methods
    ///
    /// **YouTube SDK Player (false)**
    /// - Uses official YouTube IFrame Player API via WKWebView
    /// - More reliable as it uses official APIs
    /// - Shows YouTube branding/controls
    /// - Better compatibility with YouTube's terms of service
    static let useDirectPlayer: Bool = true
    
    // MARK: - Player Settings
    
    /// Auto-play video when loaded
    static let autoPlay: Bool = true
    
    /// Show YouTube branding in SDK player
    static let showYouTubeBranding: Bool = false
    
    /// Enable inline playback (vs fullscreen)
    static let playInline: Bool = true
    
    /// Enable related videos at end
    static let showRelatedVideos: Bool = false
}
