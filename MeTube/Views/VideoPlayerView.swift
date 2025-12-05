//
//  VideoPlayerView.swift
//  MeTube
//
//  Video player view with YouTube embedding and AirPlay support
//

import SwiftUI
import WebKit
import AVKit

// MARK: - YouTube Embed Configuration

/// Configuration for YouTube embed player
enum YouTubeEmbedConfig {
    /// Base URL for YouTube embed
    static let baseURL = "https://www.youtube.com/embed/"
    
    /// YouTube embed parameters for distraction-free playback
    /// - autoplay: Start playing immediately
    /// - playsinline: Play inline on iOS instead of fullscreen
    /// - modestbranding: Reduce YouTube branding
    /// - rel: Don't show related videos at end
    /// - fs: Allow fullscreen
    /// - controls: Show player controls
    static let embedParameters = "autoplay=1&playsinline=1&modestbranding=1&rel=0&fs=1&controls=1"
    
    /// Build the full embed URL for a video ID
    static func embedURL(for videoId: String) -> String {
        let url = "\(baseURL)\(videoId)?\(embedParameters)"
        appLog("Building embed URL for video: \(videoId)", category: .player, level: .debug, context: ["url": url])
        return url
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
    @State private var currentVideoId: String
    @State private var webViewLoaded = false
    
    init(video: Video, onDismiss: @escaping () -> Void, onMarkWatched: @escaping () -> Void, nextVideo: Video? = nil, onNextVideo: ((Video) -> Void)? = nil) {
        self.video = video
        self.onDismiss = onDismiss
        self.onMarkWatched = onMarkWatched
        self.nextVideo = nextVideo
        self.onNextVideo = onNextVideo
        self._currentVideoId = State(initialValue: video.id)
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
                
                // YouTube Player
                YouTubePlayerView(videoId: currentVideoId, onLoaded: {
                    appLog("YouTube player loaded for video: \(currentVideoId)", category: .player, level: .success)
                    webViewLoaded = true
                }, onError: { errorMessage in
                    appLog("YouTube player error: \(errorMessage)", category: .player, level: .error)
                })
                .edgesIgnoringSafeArea(.all)
                .id(currentVideoId) // Force recreate when video changes
                
                // Loading indicator
                if !webViewLoaded {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Loading video...")
                            .foregroundColor(.white)
                            .padding(.top, 8)
                    }
                }
                
                // Overlay Controls
                VStack {
                    // Top Bar
                    if showingControls {
                        HStack {
                            Button(action: {
                                appLog("Dismiss button tapped", category: .player, level: .info)
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
            }
            .onDisappear {
                appLog("VideoPlayerView disappeared", category: .player, level: .info)
                controlsTimer?.invalidate()
            }
        }
        .statusBarHidden(true)
    }
    
    /// Marks the current video as watched and advances to the next video if available
    private func markWatchedAndAdvance() {
        appLog("markWatchedAndAdvance called", category: .player, level: .info, context: [
            "currentVideo": video.id,
            "hasNextVideo": nextVideo != nil
        ])
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

// MARK: - YouTube Player (WKWebView)

struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    var onLoaded: (() -> Void)?
    var onError: ((String) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded, onError: onError)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        appLog("Creating WKWebView for video: \(videoId)", category: .player, level: .debug)
        
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if the video ID has changed to prevent constant reloads
        guard context.coordinator.loadedVideoId != videoId else {
            appLog("Skipping WKWebView update - video already loaded: \(videoId)", category: .player, level: .debug)
            return
        }
        
        appLog("Updating WKWebView with videoId: \(videoId)", category: .player, level: .debug)
        
        // Mark the video as being loaded
        context.coordinator.loadedVideoId = videoId
        
        let embedURL = YouTubeEmbedConfig.embedURL(for: videoId)
        // Iframe permissions limited to only what's needed for video playback
        // - autoplay: Required for auto-starting videos
        // - encrypted-media: Required for DRM-protected content
        // - picture-in-picture: Allows PiP playback
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; }
                html, body { width: 100%; height: 100%; background-color: #000; overflow: hidden; }
                iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: none; }
            </style>
        </head>
        <body>
            <iframe
                src="\(embedURL)"
                allow="autoplay; encrypted-media; picture-in-picture"
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """
        
        appLog("Loading HTML content for video player", category: .player, level: .debug)
        webView.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.youtube.com"))
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoId: String?
        var onLoaded: (() -> Void)?
        var onError: ((String) -> Void)?
        
        init(onLoaded: (() -> Void)?, onError: ((String) -> Void)?) {
            self.loadedVideoId = nil
            self.onLoaded = onLoaded
            self.onError = onError
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            appLog("WKWebView did finish navigation", category: .player, level: .success)
            onLoaded?()
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            appLog("WKWebView navigation failed: \(error)", category: .player, level: .error)
            onError?(error.localizedDescription)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            appLog("WKWebView provisional navigation failed: \(error)", category: .player, level: .error)
            onError?(error.localizedDescription)
        }
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
