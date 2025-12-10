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
    @Binding var selectedFilter: ChannelFilter
    @Binding var searchText: String
    @Binding var isEditingSearch: Bool
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
    
    private let columns = [
        GridItem(.adaptive(minimum: 360, maximum: 400), spacing: 30)
    ]
    
    private var isSearchActive: Bool {
        !searchText.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
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
            LazyVGrid(columns: columns, spacing: 30) {
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
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: channel.thumbnailURL) { phase in
                switch phase {
                case .empty:
                    fallbackGradient
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackGradient
                        .overlay(
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 54, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        )
                @unknown default:
                    fallbackGradient
                }
            }
            .frame(width: 360, height: 202)
            .clipped()
            
            LinearGradient(
                colors: [
                    Color.black.opacity(0.75),
                    Color.black.opacity(0.12)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(width: 360, height: 202)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(channel.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(radius: 8)
                
                Spacer(minLength: 4)
            }
            .padding(16)
            
            if unwatchedCount > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(unwatchedCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                            )
                            .offset(x: -10, y: 10)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 360, height: 202)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 6)
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
    @State private var searchText: String = ""
    @State private var isEditingSearch: Bool = false
    
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
        GridItem(.adaptive(minimum: 420, maximum: 480), spacing: 32)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text(channel.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)
                
                Spacer()
                
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
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                
                Button {
                    if isEditingSearch {
                        isEditingSearch = false
                    } else if !searchText.isEmpty {
                        searchText = ""
                        isEditingSearch = false
                    } else {
                        isEditingSearch = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .imageScale(.large)
                        .foregroundColor((isEditingSearch || !searchText.isEmpty) ? .accentColor : .primary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill((isEditingSearch || !searchText.isEmpty) ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
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
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(channelVideos.filter { video in
                                if searchText.isEmpty { return true }
                                return video.title.lowercased().contains(searchText.lowercased())
                            }) { video in
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
    
    return TVChannelsView(
        selectedFilter: .constant(.withUnseenVideos),
        searchText: .constant(""),
        isEditingSearch: .constant(false)
    )
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
#endif
