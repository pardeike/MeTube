//
//  PlayerViewModel.swift
//  MeTube
//
//  ViewModel for video playback
//

import Foundation
import AVKit
import Combine

/// ViewModel for managing video playback state
@MainActor
class PlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentVideo: Video?
    @Published var isPlaying: Bool = false
    @Published var playbackProgress: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    
    // MARK: - Player
    
    /// The video player - using AVPlayer for native playback
    /// Note: For YouTube videos, we use a web-based player via WKWebView
    
    // MARK: - Callbacks
    
    /// Called when video playback completes
    var onPlaybackComplete: ((Video) -> Void)?
    
    // MARK: - Public Methods
    
    /// Loads a video for playback
    func loadVideo(_ video: Video) {
        currentVideo = video
        playbackProgress = 0
        duration = video.duration
        isPlaying = false
        error = nil
    }
    
    /// Starts playback
    func play() {
        isPlaying = true
    }
    
    /// Pauses playback
    func pause() {
        isPlaying = false
    }
    
    /// Toggles play/pause
    func togglePlayPause() {
        isPlaying.toggle()
    }
    
    /// Called when playback reaches the end
    func handlePlaybackComplete() {
        isPlaying = false
        if let video = currentVideo {
            onPlaybackComplete?(video)
        }
    }
    
    /// Updates playback progress
    func updateProgress(_ progress: Double) {
        playbackProgress = progress
    }
    
    /// Seeks to a specific time
    func seek(to time: Double) {
        playbackProgress = time
    }
    
    /// Returns the YouTube video URL for embedding
    func youtubeEmbedURL(for video: Video) -> URL? {
        // YouTube embed URL with autoplay and modest branding
        let urlString = "https://www.youtube.com/embed/\(video.id)?autoplay=1&playsinline=1&modestbranding=1&rel=0"
        return URL(string: urlString)
    }
    
    /// Returns the YouTube watch URL
    func youtubeWatchURL(for video: Video) -> URL? {
        let urlString = "https://www.youtube.com/watch?v=\(video.id)"
        return URL(string: urlString)
    }
    
    /// Clears the current video
    func clearVideo() {
        currentVideo = nil
        isPlaying = false
        playbackProgress = 0
        duration = 0
        error = nil
    }
}
