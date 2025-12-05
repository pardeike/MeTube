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
        return "\(baseURL)\(videoId)?\(embedParameters)"
    }
}

struct VideoPlayerView: View {
    let video: Video
    let onDismiss: () -> Void
    let onMarkWatched: () -> Void
    
    @State private var showingControls = true
    @State private var isFullscreen = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.edgesIgnoringSafeArea(.all)
                
                // YouTube Player
                YouTubePlayerView(videoId: video.id)
                    .edgesIgnoringSafeArea(.all)
                
                // Overlay Controls
                VStack {
                    // Top Bar
                    if showingControls {
                        HStack {
                            Button(action: onDismiss) {
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
                            
                            Button(action: onMarkWatched) {
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
            .onTapGesture {
                withAnimation {
                    showingControls.toggle()
                }
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - YouTube Player (WKWebView)

struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
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
        
        webView.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.youtube.com"))
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
        onMarkWatched: {}
    )
}
