//
//  YouTubeSDKPlayerView.swift
//  MeTube
//
//  YouTube player using WKWebView with YouTube IFrame Player API
//  This is an alternative to the direct stream player
//

import SwiftUI
import WebKit

// MARK: - YouTube SDK Player View

/// A video player that uses the official YouTube IFrame Player API via WKWebView
/// This provides better compatibility with YouTube's terms of service
/// but does not support AirPlay as seamlessly as the direct player
struct YouTubeSDKPlayerView: View {
    let videoId: String
    let autoPlay: Bool
    
    @Binding var isReady: Bool
    
    init(videoId: String, autoPlay: Bool = true, isReady: Binding<Bool> = .constant(false)) {
        self.videoId = videoId
        self.autoPlay = autoPlay
        self._isReady = isReady
    }
    
    var body: some View {
        YouTubeWebView(
            videoId: videoId,
            autoPlay: autoPlay,
            isReady: $isReady
        )
        .ignoresSafeArea(.all)
    }
}

// MARK: - WKWebView Wrapper

/// UIViewRepresentable wrapper for WKWebView to embed YouTube IFrame Player
struct YouTubeWebView: UIViewRepresentable {
    let videoId: String
    let autoPlay: Bool
    @Binding var isReady: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Allow inline playback
        configuration.allowsInlineMediaPlayback = true
        
        // Allow autoplay without user gesture for a smoother experience
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Allow AirPlay from web content
        configuration.allowsAirPlayForMediaPlayback = true
        
        // Enable JavaScript for the YouTube API
        
        // Add message handler for JavaScript communication
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "youtubePlayer")
        configuration.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        
        // Load the YouTube IFrame player
        let htmlContent = generatePlayerHTML(videoId: videoId, autoPlay: autoPlay)
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://www.youtube.com"))
        
        appLog("YouTubeSDKPlayerView: Loading video \(videoId)", category: .player, level: .info)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if video ID changed
        if context.coordinator.currentVideoId != videoId {
            appLog("YouTubeSDKPlayerView: Updating to new video \(videoId)", category: .player, level: .info)
            context.coordinator.currentVideoId = videoId
            let htmlContent = generatePlayerHTML(videoId: videoId, autoPlay: autoPlay)
            webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://www.youtube.com"))
        }
    }
    
    /// Generates the HTML content with YouTube IFrame Player API
    private func generatePlayerHTML(videoId: String, autoPlay: Bool) -> String {
        let autoPlayValue = autoPlay ? 1 : 0
        let showRelatedVideos = PlayerConfig.showRelatedVideos ? 1 : 0
        let playInline = PlayerConfig.playInline ? 1 : 0
        let modestBranding = PlayerConfig.showYouTubeBranding ? 0 : 1
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                html, body {
                    width: 100%;
                    height: 100%;
                    background-color: #000;
                    overflow: hidden;
                }
                #player {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                }
                /* Hide YouTube logo when possible */
                .ytp-watermark {
                    display: none !important;
                }
            </style>
        </head>
        <body>
            <div id="player"></div>
            
            <script>
                // Load YouTube IFrame API
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
                
                var player;
                
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        videoId: '\(videoId)',
                        playerVars: {
                            'autoplay': \(autoPlayValue),
                            'playsinline': \(playInline),
                            'rel': \(showRelatedVideos),
                            'modestbranding': \(modestBranding),
                            'controls': 1,
                            'fs': 1,
                            'enablejsapi': 1,
                            'origin': 'https://www.youtube.com'
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange,
                            'onError': onPlayerError
                        }
                    });
                }
                
                function onPlayerReady(event) {
                    // Notify Swift that player is ready
                    window.webkit.messageHandlers.youtubePlayer.postMessage({
                        event: 'ready',
                        videoId: '\(videoId)'
                    });
                    
                    // Auto-play if enabled
                    if (\(autoPlayValue) === 1) {
                        event.target.playVideo();
                    }
                }
                
                function onPlayerStateChange(event) {
                    var states = {
                        '-1': 'unstarted',
                        '0': 'ended',
                        '1': 'playing',
                        '2': 'paused',
                        '3': 'buffering',
                        '5': 'cued'
                    };
                    
                    window.webkit.messageHandlers.youtubePlayer.postMessage({
                        event: 'stateChange',
                        state: states[event.data] || 'unknown',
                        stateCode: event.data
                    });
                }
                
                function onPlayerError(event) {
                    var errors = {
                        '2': 'Invalid video ID',
                        '5': 'HTML5 player error',
                        '100': 'Video not found',
                        '101': 'Embedding not allowed',
                        '150': 'Embedding not allowed'
                    };
                    
                    window.webkit.messageHandlers.youtubePlayer.postMessage({
                        event: 'error',
                        errorCode: event.data,
                        errorMessage: errors[event.data] || 'Unknown error'
                    });
                }
                
                // Expose functions for Swift to call
                function playVideo() {
                    if (player && player.playVideo) {
                        player.playVideo();
                    }
                }
                
                function pauseVideo() {
                    if (player && player.pauseVideo) {
                        player.pauseVideo();
                    }
                }
                
                function seekTo(seconds) {
                    if (player && player.seekTo) {
                        player.seekTo(seconds, true);
                    }
                }
                
                function getCurrentTime() {
                    if (player && player.getCurrentTime) {
                        return player.getCurrentTime();
                    }
                    return 0;
                }
                
                function getDuration() {
                    if (player && player.getDuration) {
                        return player.getDuration();
                    }
                    return 0;
                }
            </script>
        </body>
        </html>
        """
    }
    
    // MARK: - Coordinator for JavaScript communication
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubeWebView
        var currentVideoId: String
        
        init(_ parent: YouTubeWebView) {
            self.parent = parent
            self.currentVideoId = parent.videoId
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String else {
                return
            }
            
            switch event {
            case "ready":
                appLog("YouTubeSDKPlayerView: Player ready", category: .player, level: .success)
                DispatchQueue.main.async {
                    self.parent.isReady = true
                }
                
            case "stateChange":
                if let state = body["state"] as? String {
                    appLog("YouTubeSDKPlayerView: State changed to \(state)", category: .player, level: .debug)
                }
                
            case "error":
                let errorCode = body["errorCode"] as? Int ?? -1
                let errorMessage = body["errorMessage"] as? String ?? "Unknown error"
                appLog("YouTubeSDKPlayerView: Error \(errorCode) - \(errorMessage)", category: .player, level: .error)
                
            default:
                break
            }
        }
    }
}

// MARK: - Preview

#Preview {
    YouTubeSDKPlayerView(
        videoId: "dQw4w9WgXcQ",
        autoPlay: false
    )
    .frame(height: 300)
    .background(Color.black)
}
