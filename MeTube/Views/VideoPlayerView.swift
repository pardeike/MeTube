//
//  VideoPlayerView.swift
//  MeTube
//
//  Video player view using native AVPlayer with AirPlay support
//  Note: Uses direct stream URL extraction for better reliability
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
}

struct VideoPlayerView: View {
    let video: Video
    let onDismiss: () -> Void
    let onMarkWatched: () -> Void
    var nextVideo: Video? = nil
    var onNextVideo: ((Video) -> Void)? = nil
    
    @State private var showingControls = true
    @State private var controlsTimer: Timer?
    @State private var loadingState: PlayerLoadingState = .idle
    @State private var player: AVPlayer?
    @State private var streamExtractor = YouTubeStreamExtractor()
    
    init(video: Video, onDismiss: @escaping () -> Void, onMarkWatched: @escaping () -> Void, nextVideo: Video? = nil, onNextVideo: ((Video) -> Void)? = nil) {
        self.video = video
        self.onDismiss = onDismiss
        self.onMarkWatched = onMarkWatched
        self.nextVideo = nextVideo
        self.onNextVideo = onNextVideo
        appLog("VideoPlayerView initialized", category: .player, level: .info, context: [
            "videoId": video.id,
            "title": video.title,
            "duration": video.duration
        ])
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.edgesIgnoringSafeArea(.all)
                
                // Native Video Player
                if let player = player {
                    NativeVideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                }
                
                // Loading / Error overlay
                if loadingState != .ready {
                    loadingOverlay
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
                            
                            // Share Button for AirPlay
                            if let player = player {
                                SharePlayButton(player: player)
                                    .frame(width: 44, height: 44)
                            }
                            
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
                                
                                // Next Video Button
                                if nextVideo != nil {
                                    Button(action: markWatchedAndAdvance) {
                                        HStack(spacing: 4) {
                                            Text("Next")
                                            Image(systemName: "forward.fill")
                                        }
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.red)
                                        .cornerRadius(16)
                                    }
                                }
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
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appLog("Player view tapped - toggling controls", category: .player, level: .debug)
                withAnimation {
                    showingControls.toggle()
                }
                resetControlsTimer()
            }
            .onAppear {
                appLog("VideoPlayerView appeared", category: .player, level: .info)
                resetControlsTimer()
                loadVideo()
            }
            .onDisappear {
                appLog("VideoPlayerView disappeared", category: .player, level: .info)
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
    
    /// Load the video by extracting the stream URL
    private func loadVideo() {
        loadingState = .extracting
        
        Task { @MainActor in
            do {
                appLog("Starting stream extraction for video: \(video.id)", category: .player, level: .info)
                let streamURL = try await streamExtractor.extractStreamURL(videoId: video.id)
                
                appLog("Stream URL extracted successfully", category: .player, level: .success, context: ["url": streamURL.absoluteString])
                
                loadingState = .loading
                
                // Create player with the extracted URL
                let playerItem = AVPlayerItem(url: streamURL)
                let newPlayer = AVPlayer(playerItem: playerItem)
                
                // Configure for AirPlay
                newPlayer.allowsExternalPlayback = true
                newPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
                
                // Set up audio session for playback
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    appLog("Failed to configure audio session: \(error)", category: .player, level: .warning)
                }
                
                self.player = newPlayer
                loadingState = .ready
                
                // Auto-play
                newPlayer.play()
                appLog("Video playback started", category: .player, level: .success)
                
            } catch {
                appLog("Failed to load video: \(error)", category: .player, level: .error)
                loadingState = .failed(error.localizedDescription)
            }
        }
    }
    
    /// Clean up player resources
    private func cleanupPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        appLog("Player cleaned up", category: .player, level: .debug)
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
        // Only update player if it's actually different and valid
        // Check both identity and current item to avoid unnecessary updates
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
    let player: AVPlayer
    @State private var showingShareSheet = false
    
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
            if let currentItem = player.currentItem,
               let asset = currentItem.asset as? AVURLAsset {
                ShareSheet(items: [asset.url])
            }
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
