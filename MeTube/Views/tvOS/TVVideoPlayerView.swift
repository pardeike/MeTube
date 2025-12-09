//
//  TVVideoPlayerView.swift
//  MeTube
//
//  tvOS-specific video player optimized for Siri Remote navigation
//  Uses AVPlayerViewController's native tvOS controls
//

import SwiftUI
import AVKit

#if os(tvOS)
struct TVVideoPlayerView: View {
    let video: Video
    let onDismiss: () -> Void
    let onMarkWatched: () -> Void
    var onMarkSkipped: (() -> Void)? = nil
    var nextVideo: Video? = nil
    var previousVideo: Video? = nil
    var onNextVideo: ((Video) -> Void)? = nil
    var onPreviousVideo: ((Video) -> Void)? = nil
    var currentIndex: Int? = nil
    var totalVideos: Int? = nil
    var savedPosition: TimeInterval = 0
    var onSavePosition: ((TimeInterval) -> Void)? = nil
    
    @State private var player: AVPlayer?
    @State private var loadingState: PlayerLoadingState = .idle
    @State private var currentPlaybackTime: TimeInterval = 0
    @State private var timeObserverToken: Any?
    @State private var hasResumedPosition = false
    @State private var lastSaveTime: TimeInterval = 0
    @State private var videoEnded = false
    @State private var endObserver: NSObjectProtocol?
    
    private let streamExtractor = YouTubeStreamExtractor.shared
    
    /// Interval in seconds between playback position saves
    private let positionSaveInterval: TimeInterval = 5.0
    
    /// Threshold for saving position as 00:00 (in seconds from beginning)
    private let nearStartThreshold: TimeInterval = 10.0
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let player = player {
                // Use native tvOS AVPlayerViewController
                TVNativeVideoPlayer(
                    player: player,
                    onDismiss: handleDismiss
                )
                .edgesIgnoringSafeArea(.all)
            }
            
            // Loading overlay
            if loadingState != .ready {
                loadingOverlay
            }
            
            // Video end overlay (dims screen when video finishes)
            if videoEnded {
                videoEndOverlay
            }
        }
        .onAppear {
            loadVideo()
            // Prevent device from sleeping during playback
            UIApplication.shared.isIdleTimerDisabled = true
            appLog("tvOS: Device sleep disabled for playback", category: .player, level: .debug)
        }
        .onDisappear {
            // Re-enable device sleep
            UIApplication.shared.isIdleTimerDisabled = false
            appLog("tvOS: Device sleep re-enabled", category: .player, level: .debug)
            checkAndMarkWatchedIfNeeded()
            cleanupPlayer()
        }
    }
    
    // MARK: - Loading Overlay
    
    @ViewBuilder
    private var loadingOverlay: some View {
        VStack(spacing: 30) {
            switch loadingState {
            case .idle, .extracting:
                ProgressView()
                    .scaleEffect(2.0)
                Text("Extracting video stream...")
                    .font(.title2)
            case .loading:
                ProgressView()
                    .scaleEffect(2.0)
                Text("Loading video...")
                    .font(.title2)
            case .failed(let error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.yellow)
                Text("Failed to load video")
                    .font(.title)
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                Button("Retry") {
                    loadVideo()
                }
                .padding(.top, 20)
            case .ready:
                EmptyView()
            }
        }
        .foregroundColor(.white)
    }
    
    /// Video end overlay (dims screen when video finishes to allow device sleep)
    @ViewBuilder
    private var videoEndOverlay: some View {
        Color.black.opacity(0.75)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                // Dismiss on tap
                handleDismiss()
            }
    }
    
    // MARK: - Video Loading
    
    private func loadVideo() {
        appLog("tvOS: Loading video: \(video.id)", category: .player, level: .info)
        loadingState = .extracting
        currentPlaybackTime = savedPosition
        hasResumedPosition = false
        lastSaveTime = 0
        
        Task { @MainActor in
            do {
                let streamURL = try await streamExtractor.extractStreamURL(videoId: video.id)
                appLog("tvOS: Stream URL extracted", category: .player, level: .success)
                
                loadingState = .loading
                
                let playerItem = AVPlayerItem(url: streamURL)
                let newPlayer = AVPlayer(playerItem: playerItem)
                
                // Configure for external playback (AirPlay, etc.)
                newPlayer.allowsExternalPlayback = true
                newPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
                
                // Configure audio session
                let audioSession = AVAudioSession.sharedInstance()
                try? audioSession.setCategory(.playback, mode: .moviePlayback)
                try? audioSession.setActive(true)
                
                self.player = newPlayer
                loadingState = .ready
                
                // Seek to saved position
                if savedPosition > 0 && !hasResumedPosition {
                    let seekTime = CMTime(seconds: savedPosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    newPlayer.seek(to: seekTime) { finished in
                        if finished {
                            self.hasResumedPosition = true
                            appLog("tvOS: Resumed from \(self.savedPosition)s", category: .player, level: .success)
                        }
                    }
                }
                
                // Set up time observer
                let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                    self.currentPlaybackTime = time.seconds
                    
                    // Save position periodically
                    if abs(time.seconds - self.lastSaveTime) >= self.positionSaveInterval {
                        self.lastSaveTime = time.seconds
                        let normalizedPosition = self.normalizePosition(time.seconds)
                        self.onSavePosition?(normalizedPosition)
                    }
                }
                
                // Remove any existing end observer before adding a new one
                if let observer = endObserver {
                    NotificationCenter.default.removeObserver(observer)
                    endObserver = nil
                }
                
                // Observe when video ends
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { [weak self] _ in
                    guard let self = self else { return }
                    appLog("tvOS: Video playback ended", category: .player, level: .info)
                    self.videoEnded = true
                    // Allow device to sleep when video ends
                    UIApplication.shared.isIdleTimerDisabled = false
                    appLog("tvOS: Device sleep enabled (video ended)", category: .player, level: .debug)
                }
                
                newPlayer.play()
                appLog("tvOS: Playback started", category: .player, level: .success)
                
            } catch {
                appLog("tvOS: Failed to load video: \(error)", category: .player, level: .error)
                loadingState = .failed(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanupPlayer() {
        if currentPlaybackTime > 0 {
            let normalizedPosition = normalizePosition(currentPlaybackTime)
            onSavePosition?(normalizedPosition)
            appLog("tvOS: Saved position: \(normalizedPosition)s (original: \(currentPlaybackTime)s)", category: .player, level: .info)
        }
        
        // Remove notification observers
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
    
    /// Normalizes playback position: positions less than 10s are saved as 0
    /// This prevents "almost start" positions from being remembered
    private func normalizePosition(_ position: TimeInterval) -> TimeInterval {
        return position < nearStartThreshold ? 0 : position
    }
    
    private func handleDismiss() {
        checkAndMarkWatchedIfNeeded()
        cleanupPlayer()
        onDismiss()
    }
    
    private func checkAndMarkWatchedIfNeeded() {
        let threshold = video.duration * 2.0 / 3.0
        if currentPlaybackTime >= threshold {
            appLog("tvOS: Video watched threshold reached", category: .player, level: .info)
            onMarkWatched()
        }
    }
}

// MARK: - Native tvOS Video Player

struct TVNativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.delegate = context.coordinator
        
        // tvOS-specific settings
        controller.allowsPictureInPicturePlayback = false // Not available on tvOS
        controller.requiresLinearPlayback = false // Allow scrubbing
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let onDismiss: () -> Void
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        
        /*
        func playerViewController(_ playerViewController: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
            // Full screen presentation starting
        }
        
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
            // User dismissed the player
            coordinator.animate(alongsideTransition: nil) { _ in
                self.onDismiss()
            }
        }
        */
    }
}

#Preview {
    TVVideoPlayerView(
        video: Video(
            id: "dQw4w9WgXcQ",
            title: "Sample Video",
            channelId: "channel1",
            channelName: "Sample Channel",
            publishedDate: Date(),
            duration: 212,
            thumbnailURL: nil
        ),
        onDismiss: {},
        onMarkWatched: {}
    )
}
#endif
