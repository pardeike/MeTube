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
}

struct VideoPlayerView: View {
    let video: Video
    let onDismiss: () -> Void
    let onMarkWatched: () -> Void
    var nextVideo: Video? = nil
    var previousVideo: Video? = nil
    var onNextVideo: ((Video) -> Void)? = nil
    var onPreviousVideo: ((Video) -> Void)? = nil
    
    @State private var showingControls = true
    @State private var controlsTimer: Timer?
    @State private var loadingState: PlayerLoadingState = .idle
    @State private var player: AVPlayer?
    @State private var showingVideoInfo = false
    @State private var sdkPlayerReady = false
    
    /// Shared stream extractor instance (only used for direct player)
    private let streamExtractor = YouTubeStreamExtractor.shared
    
    init(
        video: Video,
        onDismiss: @escaping () -> Void,
        onMarkWatched: @escaping () -> Void,
        nextVideo: Video? = nil,
        previousVideo: Video? = nil,
        onNextVideo: ((Video) -> Void)? = nil,
        onPreviousVideo: ((Video) -> Void)? = nil
    ) {
        self.video = video
        self.onDismiss = onDismiss
        self.onMarkWatched = onMarkWatched
        self.nextVideo = nextVideo
        self.previousVideo = previousVideo
        self.onNextVideo = onNextVideo
        self.onPreviousVideo = onPreviousVideo
        appLog("VideoPlayerView init called", category: .player, level: .info, context: [
            "videoId": video.id,
            "title": video.title,
            "duration": video.duration
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
                    // Top Bar
                    if showingControls {
                        HStack {
                            Button(action: {
                                appLog("Dismiss button tapped", category: .player, level: .info)
                                cleanupPlayer()
                                onDismiss()
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
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.7), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    Spacer()
                    
                    // Bottom Info Bar
                    if showingControls {
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
                        .background(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                
                // Video info sheet overlay
                if showingVideoInfo {
                    VideoInfoSheet(video: video, onDismiss: {
                        withAnimation {
                            showingVideoInfo = false
                        }
                    })
                    .transition(.move(edge: .bottom))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appLog("Player view tapped - toggling controls", category: .player, level: .debug)
                withAnimation {
                    showingControls.toggle()
                }
                resetControlsTimer()
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
                appLog("VideoPlayerView onDisappear triggered", category: .player, level: .info)
                controlsTimer?.invalidate()
                cleanupPlayer()
            }
        }
        .statusBarHidden(true)
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
        // Always cleanup AVPlayer resources if they exist
        if let player = player {
            player.pause()
            player.replaceCurrentItem(with: nil)
            self.player = nil
            appLog("Direct player cleaned up", category: .player, level: .debug)
        }
        // SDK player cleanup is handled by WKWebView's lifecycle automatically
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
            // Horizontal swipe
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
                cleanupPlayer()
                onDismiss()
            } else {
                // Swipe down - show video info
                appLog("Swipe down detected - showing video info", category: .player, level: .info)
                withAnimation {
                    showingVideoInfo = true
                }
            }
        }
    }
    
    /// Handle next video navigation
    private func handleNextVideo() {
        guard nextVideo != nil else {
            appLog("No next video available", category: .player, level: .debug)
            return
        }
        appLog("Swipe left detected - advancing to next video", category: .player, level: .info)
        markWatchedAndAdvance()
    }
    
    /// Handle previous video navigation
    private func handlePreviousVideo() {
        guard let previous = previousVideo else {
            appLog("No previous video available", category: .player, level: .debug)
            return
        }
        appLog("Swipe right detected - going to previous video", category: .player, level: .info)
        cleanupPlayer()
        onPreviousVideo?(previous)
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

// MARK: - Video Info Sheet

struct VideoInfoSheet: View {
    let video: Video
    let onDismiss: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
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
            .frame(height: geometry.size.height * 0.5)
            .background(Color.black.opacity(0.9))
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .onTapGesture {
                // Prevent dismissing when tapping content
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.height > VideoPlayerConfig.minimumDragToDismiss {
                            onDismiss()
                        }
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
    
    /// YouTube watch URL for sharing
    private var youtubeURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
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
        )
    )
}
