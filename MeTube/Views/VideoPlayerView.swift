//
//  VideoPlayerView.swift
//  MeTube
//
//  Video player view with support for two player modes:
//  1. Direct Player: Uses AVPlayer with extracted stream URLs (default)
//  2. SDK Player: Uses YouTube IFrame Player API via WKWebView
//
//  Toggle between players using PlayerConfig.useDirectPlayer
//
//  Navigation Features:
//  - Swipe up: Dismiss player
//  - Swipe down: Show video info sheet
//  - Swipe left: Next video
//  - Swipe right: Previous video
//  - Tap: Toggle controls visibility
//
//  Auto-watch: Video marked as watched if >2/3 played on dismiss
//

import SwiftUI
import AVKit

// MARK: - Player State

/// Tracks the state of video loading and playback
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

/// Configuration for video player UI
private enum VideoPlayerConfig {
    /// Duration in seconds before controls auto-hide
    static let controlsAutoHideDelay: TimeInterval = 4.0
    
    /// Minimum distance for swipe gesture recognition (in points)
    static let minimumSwipeDistance: CGFloat = 50
    
    /// Minimum drag distance to dismiss info sheet (in points)
    static let minimumDragToDismiss: CGFloat = 100
    
    /// Skip forward/backward interval in seconds
    static let skipInterval: TimeInterval = 10.0
    
    /// Animation duration for navigation transitions
    static let navigationAnimationDuration: Double = 0.3
}

struct VideoPlayerView: View {
    let video: Video
    let onDismiss: () -> Void
    let onMarkWatched: () -> Void
    var nextVideo: Video? = nil
    var previousVideo: Video? = nil
    var onNextVideo: ((Video) -> Void)? = nil
    var onPreviousVideo: ((Video) -> Void)? = nil
    /// Current position in the video list (1-based, for display)
    var currentIndex: Int? = nil
    /// Total count of videos in the list
    var totalVideos: Int? = nil
    
    @State private var showingControls = true
    @State private var controlsTimer: Timer?
    @State private var loadingState: PlayerLoadingState = .idle
    @State private var player: AVPlayer?
    @State private var showingVideoInfo = false
    @State private var currentPlaybackTime: TimeInterval = 0
    @State private var timeObserverToken: Any?
    @State private var sdkPlayerReady = false
    @State private var navigationFeedback: NavigationFeedback? = nil
    @State private var showingPlaybackControls = false
    
    /// Shared stream extractor instance (only used for direct player)
    private let streamExtractor = YouTubeStreamExtractor.shared
    
    /// Navigation feedback type for visual indicators
    enum NavigationFeedback: Equatable {
        case nextVideo
        case previousVideo
        case noNextVideo
        case noPreviousVideo
    }
    
    init(
        video: Video,
        onDismiss: @escaping () -> Void,
        onMarkWatched: @escaping () -> Void,
        nextVideo: Video? = nil,
        previousVideo: Video? = nil,
        onNextVideo: ((Video) -> Void)? = nil,
        onPreviousVideo: ((Video) -> Void)? = nil,
        currentIndex: Int? = nil,
        totalVideos: Int? = nil
    ) {
        self.video = video
        self.onDismiss = onDismiss
        self.onMarkWatched = onMarkWatched
        self.nextVideo = nextVideo
        self.previousVideo = previousVideo
        self.onNextVideo = onNextVideo
        self.onPreviousVideo = onPreviousVideo
        self.currentIndex = currentIndex
        self.totalVideos = totalVideos
        appLog("VideoPlayerView init called", category: .player, level: .info, context: [
            "videoId": video.id,
            "title": video.title,
            "duration": video.duration,
            "currentIndex": currentIndex ?? -1,
            "totalVideos": totalVideos ?? -1
        ])
    }
    
    var body: some View {
        let _ = appLog("VideoPlayerView body evaluated", category: .player, level: .debug, context: [
            "videoId": video.id,
            "useDirectPlayer": PlayerConfig.useDirectPlayer
        ])
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.edgesIgnoringSafeArea(.all)
                
                // Video Player - conditional based on PlayerConfig
                if PlayerConfig.useDirectPlayer {
                    // Direct Player (AVPlayer with extracted stream)
                    if let player = player {
                        NativeVideoPlayer(player: player)
                            .edgesIgnoringSafeArea(.all)
                    }
                } else {
                    // YouTube SDK Player (WKWebView with IFrame API)
                    YouTubeSDKPlayerView(
                        videoId: video.id,
                        autoPlay: PlayerConfig.autoPlay,
                        isReady: $sdkPlayerReady
                    )
                    .edgesIgnoringSafeArea(.all)
                }
                
                // Loading / Error overlay (only for direct player or when SDK not ready)
                if PlayerConfig.useDirectPlayer {
                    if loadingState != .ready {
                        loadingOverlay
                    }
                } else {
                    if !sdkPlayerReady {
                        sdkLoadingOverlay
                    }
                }
                
                // Overlay Controls
                VStack {
                    // Top Bar with controls and info
                    if showingControls {
                        VStack(spacing: 0) {
                            // Control buttons row
                            HStack {
                                Button(action: {
                                    appLog("Dismiss button tapped", category: .player, level: .info)
                                    dismissPlayerView()
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                
                                Spacer()
                                
                                // Share Button for YouTube URL
                                SharePlayButton(videoId: video.id)
                                    .frame(width: 44, height: 44)
                                
                                // AirPlay Button
                                AirPlayButton()
                                    .frame(width: 44, height: 44)
                                
                                Button(action: {
                                    appLog("Mark watched button tapped", category: .player, level: .info)
                                    markWatchedAndAdvance()
                                }) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                            }
                            .padding()
                            
                            // Video Info Bar (moved from bottom)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(video.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                
                                Text(video.channelName)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                HStack {
                                    Text(video.durationString)
                                    Text("•")
                                    Text(video.relativePublishDate)
                                    
                                    Spacer()
                                }
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.7), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    Spacer()
                    
                    // Bottom controls area
                    if showingControls {
                        bottomControlsOverlay
                    }
                }
                
                // Navigation feedback indicator
                if let feedback = navigationFeedback {
                    NavigationFeedbackView(feedback: feedback)
                }
                
                // Video info view (simple overlay when shown)
                if showingVideoInfo {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            // Dismiss button area
                            HStack {
                                Spacer()
                                Button(action: {
                                    showingVideoInfo = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding()
                                }
                            }
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    // Title
                                    Text(video.title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    // Channel info
                                    Text(video.channelName)
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    // Metadata
                                    HStack(spacing: 12) {
                                        Label(video.durationString, systemImage: "clock")
                                        Label(video.relativePublishDate, systemImage: "calendar")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    
                                    // Description
                                    if let description = video.description, !description.isEmpty {
                                        Divider()
                                            .background(Color.white.opacity(0.3))
                                        
                                        Text("Description")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        
                                        Text(description)
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .padding()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.95))
                    }
                }
            }
            .onTapGesture {
                // Only toggle controls if not showing video info and not tapping on controls
                if !showingVideoInfo && !showingControls {
                    appLog("Player view tapped - showing controls", category: .player, level: .debug)
                    withAnimation {
                        showingControls = true
                    }
                    resetControlsTimer()
                } else if !showingVideoInfo && showingControls {
                    // Tapping when controls are visible hides them
                    appLog("Player view tapped - hiding controls", category: .player, level: .debug)
                    withAnimation {
                        showingControls = false
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: VideoPlayerConfig.minimumSwipeDistance)
                    .onEnded { value in
                        handleSwipeGesture(value: value)
                    }
            )
            .onAppear {
                appLog("VideoPlayerView onAppear triggered", category: .player, level: .info, context: [
                    "videoId": video.id,
                    "useDirectPlayer": PlayerConfig.useDirectPlayer
                ])
                resetControlsTimer()
                // Only load video for direct player; SDK player handles its own loading
                if PlayerConfig.useDirectPlayer {
                    loadVideo()
                }
            }
            .onDisappear {
                appLog("VideoPlayerView onDisappear triggered - checking auto-watch", category: .player, level: .info, context: [
                    "videoId": video.id,
                    "currentPlaybackTime": currentPlaybackTime,
                    "duration": video.duration
                ])
                // Always check if video should be marked as watched when view disappears
                // This handles both explicit dismiss and system gesture dismiss
                checkAndMarkWatchedIfNeeded()
                controlsTimer?.invalidate()
                cleanupPlayer()
            }
    }
        .statusBarHidden(true)
    }
    
    // MARK: - Bottom Controls
    
    /// Bottom control bar with playback controls and progress
    @ViewBuilder
    private var bottomControlsOverlay: some View {
        VStack(spacing: 12) {
            // Playback progress bar (only for direct player)
            if PlayerConfig.useDirectPlayer && loadingState == .ready {
                PlaybackProgressBar(
                    currentTime: currentPlaybackTime,
                    duration: video.duration
                )
                .padding(.horizontal)
            }
            
            // Control buttons row
            HStack(spacing: 24) {
                // Previous video button
                Button(action: {
                    handlePreviousVideo()
                }) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .foregroundColor(previousVideo != nil ? .white : .white.opacity(0.3))
                }
                .disabled(previousVideo == nil)
                
                // Skip backward button
                if PlayerConfig.useDirectPlayer && player != nil {
                    Button(action: {
                        skipBackward()
                    }) {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                
                // Play/Pause (visual indicator - actual control is native player)
                if PlayerConfig.useDirectPlayer {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Skip forward button
                if PlayerConfig.useDirectPlayer && player != nil {
                    Button(action: {
                        skipForward()
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                
                // Next video button
                Button(action: {
                    handleNextVideo()
                }) {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                        .foregroundColor(nextVideo != nil ? .white : .white.opacity(0.3))
                }
                .disabled(nextVideo == nil)
            }
            .padding(.vertical, 8)
            
            // Video position indicator
            if let index = currentIndex, let total = totalVideos {
                Text("Video \(index) of \(total)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Mark as watched button (more prominent)
            Button(action: {
                markWatchedAndAdvance()
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark as Watched")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.8))
                .cornerRadius(20)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    /// Loading overlay view
    @ViewBuilder
    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            switch loadingState {
            case .idle, .extracting:
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Extracting video stream...")
                    .foregroundColor(.white)
            case .loading:
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Loading video...")
                    .foregroundColor(.white)
            case .failed(let error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.yellow)
                Text("Failed to load video")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button(action: loadVideo) {
                    Text("Retry")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .padding(.top, 8)
            case .ready:
                EmptyView()
            }
        }
    }
    
    /// Loading overlay for SDK player
    @ViewBuilder
    private var sdkLoadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading YouTube player...")
                .foregroundColor(.white)
        }
    }
    
    /// Load the video by extracting the stream URL
    private func loadVideo() {
        appLog("loadVideo() called for video: \(video.id)", category: .player, level: .info)
        loadingState = .extracting
        currentPlaybackTime = 0 // Reset playback time for new video
        appLog("Loading state set to: extracting", category: .player, level: .debug)
        
        Task { @MainActor in
            appLog("Task started for stream extraction", category: .player, level: .debug)
            do {
                appLog("Starting stream extraction for video: \(video.id)", category: .player, level: .info)
                let streamURL = try await streamExtractor.extractStreamURL(videoId: video.id)
                
                appLog("Stream URL extracted successfully", category: .player, level: .success, context: ["url": streamURL.absoluteString])
                
                loadingState = .loading
                appLog("Loading state set to: loading", category: .player, level: .debug)
                
                // Create player with the extracted URL
                appLog("Creating AVPlayerItem with URL", category: .player, level: .debug)
                let playerItem = AVPlayerItem(url: streamURL)
                let newPlayer = AVPlayer(playerItem: playerItem)
                appLog("AVPlayer created", category: .player, level: .debug)
                
                // Configure for AirPlay
                newPlayer.allowsExternalPlayback = true
                newPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
                
                // Set up audio session for playback
                let audioSession = AVAudioSession.sharedInstance()
                do {
                    try audioSession.setCategory(.playback, mode: .moviePlayback)
                    try audioSession.setActive(true)
                    appLog("Audio session configured successfully", category: .player, level: .debug)
                } catch {
                    appLog("Failed to configure audio session: \(error)", category: .player, level: .warning)
                }
                
                self.player = newPlayer
                loadingState = .ready
                appLog("Loading state set to: ready", category: .player, level: .debug)
                
                // Set up periodic time observer to track playback position
                let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                    self.currentPlaybackTime = time.seconds
                }
                appLog("Time observer set up", category: .player, level: .debug)
                
                // Auto-play
                newPlayer.play()
                appLog("Video playback started", category: .player, level: .success)
                
            } catch {
                appLog("Failed to load video: \(error)", category: .player, level: .error, context: [
                    "videoId": video.id,
                    "errorDescription": error.localizedDescription
                ])
                loadingState = .failed(error.localizedDescription)
            }
        }
    }
    
    /// Clean up player resources
    private func cleanupPlayer() {
        // Remove time observer
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        appLog("Player cleaned up", category: .player, level: .debug)
    }
    
    /// Dismisses the player view
    private func dismissPlayerView() {
        appLog("dismissPlayerView() called explicitly", category: .player, level: .info, context: [
            "videoId": video.id
        ])
        // Don't check auto-watch here - it's handled in onDisappear
        // This ensures auto-watch happens regardless of dismiss method
        onDismiss()
    }
    
    /// Checks if video should be marked as watched based on playback position
    /// Marks video as watched if playback position is over 2/3 of the video duration
    private func checkAndMarkWatchedIfNeeded() {
        let threshold = video.duration * 2.0 / 3.0
        if currentPlaybackTime >= threshold {
            appLog("Video watched threshold reached (\(currentPlaybackTime)s / \(video.duration)s)", 
                   category: .player, level: .info, context: [
                "videoId": video.id,
                "currentTime": currentPlaybackTime,
                "duration": video.duration,
                "threshold": threshold
            ])
            onMarkWatched()
        } else {
            appLog("Video not watched enough (\(currentPlaybackTime)s / \(video.duration)s)", 
                   category: .player, level: .debug, context: [
                "videoId": video.id,
                "currentTime": currentPlaybackTime,
                "duration": video.duration,
                "threshold": threshold
            ])
        }
    }
    
    /// Marks the current video as watched and advances to the next video if available
    private func markWatchedAndAdvance() {
        appLog("markWatchedAndAdvance called", category: .player, level: .info, context: [
            "currentVideo": video.id,
            "hasNextVideo": nextVideo != nil
        ])
        cleanupPlayer()
        onMarkWatched()
        if let next = nextVideo {
            appLog("Advancing to next video: \(next.id)", category: .player, level: .info)
            onNextVideo?(next)
        }
    }
    
    /// Handles swipe gestures for player navigation
    private func handleSwipeGesture(value: DragGesture.Value) {
        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height
        
        // Determine if swipe is more horizontal or vertical
        if abs(horizontalAmount) > abs(verticalAmount) {
            // Horizontal swipe - switch videos in-place
            if horizontalAmount > 0 {
                // Swipe right - previous video
                handlePreviousVideo()
            } else {
                // Swipe left - next video
                handleNextVideo()
            }
        } else {
            // Vertical swipe
            if verticalAmount < 0 {
                // Swipe up - dismiss player
                appLog("Swipe up detected - dismissing player", category: .player, level: .info)
                dismissPlayerView()
            } else if verticalAmount > 0 {
                // Swipe down - show info sheet
                appLog("Swipe down detected - showing info sheet", category: .player, level: .info)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingVideoInfo = true
                }
            }
        }
    }
    
    /// Handle next video navigation - switch in-place
    private func handleNextVideo() {
        guard let next = nextVideo else {
            appLog("No next video available", category: .player, level: .debug)
            showNavigationFeedback(.noNextVideo)
            return
        }
        appLog("Swipe left detected - advancing to next video", category: .player, level: .info)
        showNavigationFeedback(.nextVideo)
        // Auto-watch check will happen in onDisappear when view is recreated
        // Switch to next video in-place (with slight delay for feedback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.onNextVideo?(next)
        }
    }
    
    /// Handle previous video navigation - switch in-place
    private func handlePreviousVideo() {
        guard let previous = previousVideo else {
            appLog("No previous video available", category: .player, level: .debug)
            showNavigationFeedback(.noPreviousVideo)
            return
        }
        appLog("Swipe right detected - going to previous video", category: .player, level: .info)
        showNavigationFeedback(.previousVideo)
        // Auto-watch check will happen in onDisappear when view is recreated
        // Switch to previous video in-place (with slight delay for feedback)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.onPreviousVideo?(previous)
        }
    }
    
    /// Skip forward by the configured interval
    private func skipForward() {
        guard let player = player else { return }
        let newTime = min(currentPlaybackTime + VideoPlayerConfig.skipInterval, video.duration)
        let cmTime = CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime) { _ in
            appLog("Skipped forward to \(newTime)s", category: .player, level: .debug)
        }
    }
    
    /// Skip backward by the configured interval
    private func skipBackward() {
        guard let player = player else { return }
        let newTime = max(currentPlaybackTime - VideoPlayerConfig.skipInterval, 0)
        let cmTime = CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime) { _ in
            appLog("Skipped backward to \(newTime)s", category: .player, level: .debug)
        }
    }
    
    /// Shows navigation feedback indicator
    private func showNavigationFeedback(_ feedback: NavigationFeedback) {
        withAnimation(.easeIn(duration: 0.15)) {
            navigationFeedback = feedback
        }
        // Auto-hide after brief display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.2)) {
                self.navigationFeedback = nil
            }
        }
    }
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        if showingControls {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: VideoPlayerConfig.controlsAutoHideDelay, repeats: false) { _ in
                withAnimation {
                    showingControls = false
                }
            }
        }
    }
}

// MARK: - Navigation Feedback View

/// Visual feedback indicator for navigation gestures
struct NavigationFeedbackView: View {
    let feedback: VideoPlayerView.NavigationFeedback
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title)
            Text(message)
                .font(.headline)
        }
        .foregroundColor(isError ? .orange : .white)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.8))
        )
    }
    
    private var iconName: String {
        switch feedback {
        case .nextVideo:
            return "forward.end.fill"
        case .previousVideo:
            return "backward.end.fill"
        case .noNextVideo:
            return "exclamationmark.circle"
        case .noPreviousVideo:
            return "exclamationmark.circle"
        }
    }
    
    private var message: String {
        switch feedback {
        case .nextVideo:
            return "Next Video"
        case .previousVideo:
            return "Previous Video"
        case .noNextVideo:
            return "No More Videos"
        case .noPreviousVideo:
            return "First Video"
        }
    }
    
    private var isError: Bool {
        switch feedback {
        case .noNextVideo, .noPreviousVideo:
            return true
        default:
            return false
        }
    }
}

// MARK: - Playback Progress Bar

/// Simple playback progress indicator
struct PlaybackProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    
    var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: progressWidth(for: geometry.size.width), height: 4)
                }
            }
            .frame(height: 4)
            
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    private func progressWidth(for totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let progress = min(currentTime / duration, 1.0)
        return totalWidth * CGFloat(progress)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

struct VideoInfoSheet: View {
    let video: Video
    @Binding var offset: CGFloat
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let sheetHeight = geometry.size.height * 0.5
            
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text(video.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        // Channel info
                        HStack {
                            Text(video.channelName)
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }
                        
                        // Metadata
                        HStack(spacing: 12) {
                            Label(video.durationString, systemImage: "clock")
                            Label(video.relativePublishDate, systemImage: "calendar")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        
                        // Description
                        if let description = video.description, !description.isEmpty {
                            Divider()
                                .background(Color.white.opacity(0.3))
                            
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text(description)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: sheetHeight)
            .background(Color.black.opacity(0.9))
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .offset(y: dragOffset) // Apply drag offset during gesture
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Allow dragging down (positive) to hide, and dragging up (negative) to show
                        let newOffset = value.translation.height
                        // Clamp between fully visible and hidden
                        // When offset is 0 (hidden), can only drag up (negative)
                        // When offset is -sheetHeight (visible), can drag down (positive) to hide
                        if offset == 0 {
                            // Sheet is hidden, allow dragging up to show
                            dragOffset = min(0, newOffset)
                        } else {
                            // Sheet is visible or partially visible
                            let targetOffset = offset + newOffset
                            dragOffset = max(offset, min(0, targetOffset)) - offset
                        }
                    }
                    .onEnded { value in
                        let velocity = value.predictedEndTranslation.height - value.translation.height
                        let finalOffset = offset + value.translation.height
                        
                        // Determine if sheet should snap to visible or hidden
                        let shouldShow = finalOffset < -sheetHeight / 3 || velocity < -100
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if shouldShow {
                                offset = -sheetHeight
                            } else {
                                offset = 0
                            }
                        }
                        dragOffset = 0
                    }
            )
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Native Video Player (AVPlayerViewController)

struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.videoGravity = .resizeAspect
        
        // Enable AirPlay
        controller.player?.allowsExternalPlayback = true
        
        appLog("AVPlayerViewController created", category: .player, level: .debug)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Only update player if the instance has changed (identity check)
        guard uiViewController.player !== player else { return }
        
        appLog("Updating AVPlayerViewController with new player", category: .player, level: .debug)
        uiViewController.player = player
    }
}

// MARK: - AirPlay Button

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = .white
        routePickerView.activeTintColor = .systemBlue
        routePickerView.prioritizesVideoDevices = true
        return routePickerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Share Button for AirPlay/External Playback

struct SharePlayButton: View {
    let videoId: String
    @State private var showingShareSheet = false
    
    /// Fallback URL for YouTube (guaranteed to be valid at compile time)
    private static let fallbackURL = URL(string: "https://www.youtube.com")!
    
    /// YouTube watch URL for sharing
    private var youtubeURL: URL {
        // Use addingPercentEncoding to handle any special characters in videoId
        let encodedVideoId = videoId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? videoId
        return URL(string: "https://www.youtube.com/watch?v=\(encodedVideoId)") ?? Self.fallbackURL
    }
    
    var body: some View {
        Button(action: {
            showingShareSheet = true
        }) {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [youtubeURL])
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    VideoPlayerView(
        video: Video(
            id: "dQw4w9WgXcQ",
            title: "Sample Video Title That Could Be Very Long",
            channelId: "channel1",
            channelName: "Sample Channel",
            publishedDate: Date(),
            duration: 212,
            thumbnailURL: nil
        ),
        onDismiss: {},
        onMarkWatched: {},
        nextVideo: Video(
            id: "next123",
            title: "Next Video",
            channelId: "channel1",
            channelName: "Sample Channel",
            publishedDate: Date(),
            duration: 300,
            thumbnailURL: nil
        ),
        previousVideo: Video(
            id: "prev123",
            title: "Previous Video",
            channelId: "channel1",
            channelName: "Sample Channel",
            publishedDate: Date(),
            duration: 180,
            thumbnailURL: nil
        ),
        currentIndex: 5,
        totalVideos: 10
    )
}
