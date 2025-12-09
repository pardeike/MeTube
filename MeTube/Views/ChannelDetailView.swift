//
//  ChannelDetailView.swift
//  MeTube
//
//  Detail view for a specific channel showing its videos
//  Note: iOS only - tvOS uses TVChannelDetailView
//

import SwiftUI
import SwiftData

// ChannelVideoFilter enum is defined in SharedTypes.swift

#if os(iOS)
struct ChannelDetailView: View {
    let channel: Channel
    @EnvironmentObject var feedViewModel: FeedViewModel
    @State private var selectedVideo: Video?
    @State private var selectedFilter: ChannelVideoFilter = .all
    @State private var searchText: String = ""
    
    var channelVideos: [Video] {
        // Get all videos for this channel
        var videos = feedViewModel.videos(for: channel.id)
        
        // Apply status filter
        switch selectedFilter {
        case .all:
            // Show all videos
            break
        case .unwatched:
            videos = videos.filter { $0.status == .unwatched }
        case .skipped:
            videos = videos.filter { $0.status == .skipped }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            videos = videos.filter { video in
                video.title.lowercased().contains(lowercasedSearch)
            }
        }
        
        // Videos are already sorted descending by date in feedViewModel.videos()
        return videos
    }
    
    var body: some View {
        Group {
            if channelVideos.isEmpty {
                EmptyChannelView(selectedFilter: selectedFilter)
            } else {
                VideoListView(
                    videos: channelVideos,
                    onVideoTap: { video in
                        selectedVideo = video
                    },
                    onToggleWatched: { video in
                        Task {
                            if video.status == .watched {
                                await feedViewModel.markAsUnwatched(video)
                            } else {
                                await feedViewModel.markAsWatched(video)
                            }
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
        .searchable(text: $searchText, prompt: "Search videos in this channel")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Filter options
                    ForEach(ChannelVideoFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            selectedFilter = filter
                        }) {
                            if selectedFilter == filter {
                                Label(filter.rawValue, systemImage: "checkmark")
                            } else {
                                Text(filter.rawValue)
                            }
                        }
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
        .fullScreenCover(item: $selectedVideo) { video in
            let nextVideo = getNextVideo(after: video)
            let previousVideo = getPreviousVideo(before: video)
            let videoIndex = getVideoIndex(for: video)
            let savedPosition = feedViewModel.getPlaybackPosition(for: video.id)
            VideoPlayerView(
                video: video,
                onDismiss: {
                    selectedVideo = nil
                },
                onMarkWatched: {
                    Task {
                        await feedViewModel.markAsWatched(video)
                    }
                },
                onMarkSkipped: {
                    Task {
                        await feedViewModel.markAsSkipped(video)
                    }
                },
                // No onGoToChannel in ChannelDetailView since we're already on the channel
                nextVideo: nextVideo,
                previousVideo: previousVideo,
                onNextVideo: { next in
                    selectedVideo = next
                },
                onPreviousVideo: { previous in
                    selectedVideo = previous
                },
                currentIndex: videoIndex,
                totalVideos: channelVideos.count,
                savedPosition: savedPosition,
                onSavePosition: { position in
                    feedViewModel.savePlaybackPosition(for: video.id, position: position)
                }
            )
        }
    }
    
    /// Gets the 1-based index of the video in the channel's video list
    private func getVideoIndex(for video: Video) -> Int? {
        guard let index = channelVideos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        return index + 1 // Convert to 1-based index
    }
    
    /// Gets the next video after the current one in this channel
    private func getNextVideo(after video: Video) -> Video? {
        guard let currentIndex = channelVideos.firstIndex(where: { $0.id == video.id }) else {
            return channelVideos.first
        }
        let nextIndex = currentIndex + 1
        return nextIndex < channelVideos.count ? channelVideos[nextIndex] : nil
    }
    
    /// Gets the previous video before the current one in this channel
    private func getPreviousVideo(before video: Video) -> Video? {
        guard let currentIndex = channelVideos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        let previousIndex = currentIndex - 1
        return previousIndex >= 0 ? channelVideos[previousIndex] : nil
    }
}

struct EmptyChannelView: View {
    let selectedFilter: ChannelVideoFilter
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedFilter == .all ? "video.slash" : "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(selectedFilter == .all ? .secondary : .green)
            
            Text(emptyMessage)
                .font(.headline)
            
            Text(emptyDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var emptyMessage: String {
        switch selectedFilter {
        case .all:
            return "No videos available"
        case .unwatched:
            return "All caught up!"
        case .skipped:
            return "No skipped videos"
        }
    }
    
    private var emptyDescription: String {
        switch selectedFilter {
        case .all:
            return "This channel has no recent videos"
        case .unwatched:
            return "You've watched all videos from this channel"
        case .skipped:
            return "You haven't skipped any videos from this channel"
        }
    }
}

#Preview {
    // Create a temporary in-memory ModelContext for preview
    let schema = Schema([VideoEntity.self, ChannelEntity.self, StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let viewModel = FeedViewModel(modelContext: context)
    
    return NavigationView {
        ChannelDetailView(channel: Channel(
            id: "test",
            name: "Test Channel",
            thumbnailURL: nil,
            description: "A test channel"
        ))
        .environmentObject(viewModel)
    }
}
#endif // os(iOS)
