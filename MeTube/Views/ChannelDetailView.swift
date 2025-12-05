//
//  ChannelDetailView.swift
//  MeTube
//
//  Detail view for a specific channel showing its videos
//

import SwiftUI

struct ChannelDetailView: View {
    let channel: Channel
    @EnvironmentObject var feedViewModel: FeedViewModel
    @State private var selectedVideo: Video?
    @State private var showingPlayer = false
    @State private var showAllVideos = false
    
    var channelVideos: [Video] {
        let videos = feedViewModel.videos(for: channel.id)
        if showAllVideos {
            return videos
        } else {
            return videos.filter { $0.status == .unwatched }
        }
    }
    
    var body: some View {
        Group {
            if channelVideos.isEmpty {
                EmptyChannelView(showAllVideos: showAllVideos)
            } else {
                VideoListView(
                    videos: channelVideos,
                    onVideoTap: { video in
                        selectedVideo = video
                        showingPlayer = true
                    },
                    onMarkWatched: { video in
                        Task {
                            await feedViewModel.markAsWatched(video)
                        }
                    },
                    onMarkSkipped: { video in
                        Task {
                            await feedViewModel.markAsSkipped(video)
                        }
                    }
                )
            }
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: {
                        showAllVideos = false
                    }) {
                        Label("Unwatched Only", systemImage: showAllVideos ? "" : "checkmark")
                    }
                    
                    Button(action: {
                        showAllVideos = true
                    }) {
                        Label("All Videos", systemImage: showAllVideos ? "checkmark" : "")
                    }
                    
                    Divider()
                    
                    Button(action: {
                        Task {
                            await feedViewModel.markChannelAsWatched(channel.id)
                        }
                    }) {
                        Label("Mark All as Watched", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            if let video = selectedVideo {
                let nextVideo = getNextVideo(after: video)
                VideoPlayerView(
                    video: video,
                    onDismiss: {
                        showingPlayer = false
                    },
                    onMarkWatched: {
                        Task {
                            await feedViewModel.markAsWatched(video)
                        }
                    },
                    nextVideo: nextVideo,
                    onNextVideo: { next in
                        selectedVideo = next
                    }
                )
            }
        }
    }
    
    /// Gets the next video after the current one in this channel
    private func getNextVideo(after video: Video) -> Video? {
        guard let currentIndex = channelVideos.firstIndex(where: { $0.id == video.id }) else {
            return channelVideos.first
        }
        let nextIndex = currentIndex + 1
        return nextIndex < channelVideos.count ? channelVideos[nextIndex] : nil
    }
}

struct EmptyChannelView: View {
    let showAllVideos: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text(showAllVideos ? "No videos available" : "All caught up!")
                .font(.headline)
            
            Text(showAllVideos ? "This channel has no recent videos" : "You've watched all videos from this channel")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    NavigationView {
        ChannelDetailView(channel: Channel(
            id: "test",
            name: "Test Channel",
            thumbnailURL: nil,
            description: "A test channel"
        ))
        .environmentObject(FeedViewModel())
    }
}
