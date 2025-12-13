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
    @Binding var selectedFilter: ChannelFilter
    @Binding var searchText: String
    @Binding var isEditingSearch: Bool
    @Binding var videoFilter: ChannelVideoFilter
    @Binding var videoSearchText: String
    @Binding var videoIsEditingSearch: Bool
    @Binding var isInChannelDetail: Bool
    @FocusState private var searchFieldFocused: Bool
    
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
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        isInChannelDetail = false
                    }
                
                if isEditingSearch {
                    TextField("Search channels", text: $searchText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 40)
                        .focused($searchFieldFocused)
                        .onSubmit {
                            isEditingSearch = false
                            searchFieldFocused = false
                        }
                }
                
                Group {
                    if feedViewModel.isLoading && feedViewModel.channels.isEmpty {
                        TVLoadingView(loadingState: feedViewModel.loadingState)
                    } else if filteredChannels.isEmpty {
                        TVEmptyChannelsView(hasChannels: !feedViewModel.channels.isEmpty)
                    } else {
                        channelGridView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: isEditingSearch) { _, editing in
                if editing {
                    searchFieldFocused = true
                } else {
                    searchFieldFocused = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var channelGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(filteredChannels) { channel in
                    NavigationLink(destination:
                        TVChannelDetailView(
                            channel: channel,
                            selectedFilter: $videoFilter,
                            searchText: $videoSearchText,
                            isEditingSearch: $videoIsEditingSearch,
                            isInChannelDetail: $isInChannelDetail
                        )
                    ) {
                        TVChannelCardView(
                            channel: channel,
                            unwatchedCount: feedViewModel.unwatchedCount(for: channel.id),
                            totalVideoCount: feedViewModel.totalVideoCount(for: channel.id)
                        )
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
    }
}

// MARK: - Channel Card View

struct TVChannelCardView: View {
    let channel: Channel
    let unwatchedCount: Int
    let totalVideoCount: Int
    
    private let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            fallbackGradient
            
            AsyncImage(url: channel.thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Color.clear
                        .overlay(
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 54, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        )
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color.clear
                        .overlay(
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 54, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        )
                @unknown default:
                    Color.clear
                        .overlay(
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 54, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            gradientOverlay
            textOverlay
        }
        .overlay(alignment: .topTrailing) {
            if unwatchedCount > 0 {
                Circle()
                    .fill(Color.red)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("\(unwatchedCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                    .padding(.trailing, 10)
                    .padding(.top, 10)
            } else if totalVideoCount > 0 {
                Circle()
                    .fill(Color.gray.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("\(totalVideoCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                    .padding(.trailing, 10)
                    .padding(.top, 10)
            }
        }
        .clipShape(cardShape)
        .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 6)
        .frame(maxWidth: .infinity)
        .aspectRatio(16/9, contentMode: .fit)
        .contentShape(cardShape)
    }
    
    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(channel.name)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(radius: 8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(16)
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.75),
                Color.black.opacity(0.12)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var fallbackGradient: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.8),
                Color.purple.opacity(0.7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @Binding var selectedFilter: ChannelVideoFilter
    @Binding var searchText: String
    @Binding var isEditingSearch: Bool
    @Binding var isInChannelDetail: Bool
    
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
        
        if !searchText.isEmpty {
            let lowered = searchText.lowercased()
            videos = videos.filter { $0.title.lowercased().contains(lowered) }
        }
        
        return videos
    }
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text(channel.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 28)
            
            if isEditingSearch {
                TextField("Search videos in \(channel.name)", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 40)
                    .onSubmit {
                        isEditingSearch = false
                    }
            }
            
            Group {
                if channelVideos.isEmpty {
                    TVEmptyChannelVideosView(selectedFilter: selectedFilter)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
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
                        .padding(.horizontal, 28)
                        .padding(.vertical, 32)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(false)
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
        .onAppear {
            isInChannelDetail = true
        }
        .onDisappear {
            isInChannelDetail = false
            isEditingSearch = false
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
    let schema = Schema([StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let viewModel = FeedViewModel(modelContext: context)
    
    TVChannelsView(
        selectedFilter: .constant(.withUnseenVideos),
        searchText: .constant(""),
        isEditingSearch: .constant(false),
        videoFilter: .constant(.all),
        videoSearchText: .constant(""),
        videoIsEditingSearch: .constant(false),
        isInChannelDetail: .constant(false)
    )
        .environmentObject(viewModel)
}
#endif
