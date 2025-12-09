//
//  TVChannelsView.swift
//  MeTube
//
//  tvOS-specific channels view with focus navigation
//

import SwiftUI
import SwiftData

#if os(tvOS)
struct TVChannelsView: View {
    @EnvironmentObject var feedViewModel: FeedViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var searchText: String = ""
    @State private var selectedFilter: ChannelFilter = .all
    
    var filteredChannels: [Channel] {
        var channels = feedViewModel.channels
        
        // Apply filter
        if selectedFilter == .withUnseenVideos {
            channels = channels.filter { channel in
                feedViewModel.unwatchedCount(for: channel.id) > 0
            }
        }
        
        // Apply search
        if !searchText.isEmpty {
            channels = channels.filter {
                $0.name.lowercased().contains(searchText.lowercased())
            }
        }
        
        return channels
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 40)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                if feedViewModel.isLoading && feedViewModel.channels.isEmpty {
                    TVLoadingView(loadingState: feedViewModel.loadingState)
                } else if filteredChannels.isEmpty {
                    TVEmptyChannelsView(hasChannels: !feedViewModel.channels.isEmpty)
                } else {
                    channelGridView
                }
            }
            .navigationTitle("Channels")
            .searchable(text: $searchText, prompt: "Search channels")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Filter") {
                            Button(action: { selectedFilter = .all }) {
                                if selectedFilter == .all {
                                    Label("All Channels", systemImage: "checkmark")
                                } else {
                                    Text("All Channels")
                                }
                            }
                            
                            Button(action: { selectedFilter = .withUnseenVideos }) {
                                if selectedFilter == .withUnseenVideos {
                                    Label("With Unseen Videos", systemImage: "checkmark")
                                } else {
                                    Text("With Unseen Videos")
                                }
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var channelGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(filteredChannels) { channel in
                    NavigationLink(destination: TVChannelDetailView(channel: channel)) {
                        TVChannelCardView(
                            channel: channel,
                            unwatchedCount: feedViewModel.unwatchedCount(for: channel.id)
                        )
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
    }
}

// MARK: - Channel Card View

struct TVChannelCardView: View {
    let channel: Channel
    let unwatchedCount: Int
    
    var body: some View {
        VStack(spacing: 16) {
            // Channel Thumbnail
            AsyncImage(url: channel.thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                case .failure:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                        )
                @unknown default:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                }
            }
            
            VStack(spacing: 8) {
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if unwatchedCount > 0 {
                    Text("\(unwatchedCount) unwatched")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                }
            }
        }
        .frame(width: 200)
        .padding()
    }
}

// MARK: - Empty Channels View

struct TVEmptyChannelsView: View {
    let hasChannels: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "person.3")
                .font(.system(size: 100))
                .foregroundColor(.secondary)
            
            if hasChannels {
                Text("No channels match your search")
                    .font(.title)
            } else {
                Text("No subscriptions found")
                    .font(.title)
                Text("Make sure you're subscribed to channels on YouTube")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Channel Detail View

struct TVChannelDetailView: View {
    let channel: Channel
    @EnvironmentObject var feedViewModel: FeedViewModel
    @State private var selectedVideo: Video?
    @State private var selectedFilter: ChannelVideoFilter = .all
    
    var channelVideos: [Video] {
        var videos = feedViewModel.videos(for: channel.id)
        
        switch selectedFilter {
        case .all:
            break
        case .unwatched:
            videos = videos.filter { $0.status == .unwatched }
        case .skipped:
            videos = videos.filter { $0.status == .skipped }
        }
        
        return videos
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 40)
    ]
    
    var body: some View {
        Group {
            if channelVideos.isEmpty {
                TVEmptyChannelVideosView(selectedFilter: selectedFilter)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(channelVideos) { video in
                            Button(action: {
                                selectedVideo = video
                            }) {
                                TVVideoCardView(video: video)
                            }
                            .buttonStyle(.card)
                            .contextMenu {
                                Button {
                                    Task {
                                        if video.status == .watched {
                                            await feedViewModel.markAsUnwatched(video)
                                        } else {
                                            await feedViewModel.markAsWatched(video)
                                        }
                                    }
                                } label: {
                                    Label(
                                        video.status == .watched ? "Mark as Unwatched" : "Mark as Watched",
                                        systemImage: video.status == .watched ? "arrow.uturn.backward.circle" : "checkmark.circle"
                                    )
                                }
                                
                                Button {
                                    Task {
                                        await feedViewModel.markAsSkipped(video)
                                    }
                                } label: {
                                    Label("Skip Video", systemImage: "forward.fill")
                                }
                            }
                        }
                    }
                    .padding(60)
                }
            }
        }
        .navigationTitle(channel.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ChannelVideoFilter.allCases, id: \.self) { filter in
                        Button(action: { selectedFilter = filter }) {
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
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            TVVideoPlayerView(
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
                nextVideo: getNextVideo(after: video),
                previousVideo: getPreviousVideo(before: video),
                onNextVideo: { next in
                    selectedVideo = next
                },
                onPreviousVideo: { previous in
                    selectedVideo = previous
                },
                currentIndex: getVideoIndex(for: video),
                totalVideos: channelVideos.count,
                savedPosition: feedViewModel.getPlaybackPosition(for: video.id),
                onSavePosition: { position in
                    feedViewModel.savePlaybackPosition(for: video.id, position: position)
                }
            )
        }
    }
    
    private func getVideoIndex(for video: Video) -> Int? {
        guard let index = channelVideos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        return index + 1
    }
    
    private func getNextVideo(after video: Video) -> Video? {
        guard let currentIndex = channelVideos.firstIndex(where: { $0.id == video.id }) else {
            return channelVideos.first
        }
        let nextIndex = currentIndex + 1
        return nextIndex < channelVideos.count ? channelVideos[nextIndex] : nil
    }
    
    private func getPreviousVideo(before video: Video) -> Video? {
        guard let currentIndex = channelVideos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        let previousIndex = currentIndex - 1
        return previousIndex >= 0 ? channelVideos[previousIndex] : nil
    }
}

struct TVEmptyChannelVideosView: View {
    let selectedFilter: ChannelVideoFilter
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: selectedFilter == .all ? "video.slash" : "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(selectedFilter == .all ? .secondary : .green)
            
            Text(emptyMessage)
                .font(.title)
            
            Text(emptyDescription)
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
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
    let schema = Schema([VideoEntity.self, ChannelEntity.self, StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let viewModel = FeedViewModel(modelContext: context)
    
    return TVChannelsView()
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
#endif
