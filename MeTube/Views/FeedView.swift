//
//  FeedView.swift
//  MeTube
//
//  Main subscription feed view showing unwatched videos
//  Note: iOS only - tvOS uses TVFeedView
//

import SwiftUI
import SwiftData

#if os(iOS)
struct FeedView: View {
    @EnvironmentObject var feedViewModel: FeedViewModel
    @State private var selectedVideo: Video?
    @State private var showingError = false
    @State private var selectedChannelId: String? = nil
    @State private var showingMarkAllWatchedConfirmation = false
    @State private var markAllWatchedVideoIds: [String] = []
    
    private func handleVideoTap(_ video: Video) {
        appLog("Selecting video for playback: \(video.title)", category: .ui, level: .info, context: [
            "videoId": video.id,
            "duration": video.duration
        ])
        selectedVideo = video
    }

    private func handleToggleWatched(_ video: Video) {
        Task {
            if video.status == .watched {
                await feedViewModel.markAsUnwatched(video)
            } else {
                await feedViewModel.markAsWatched(video)
            }
        }
    }

    private func handleMarkSkipped(_ video: Video) {
        Task {
            await feedViewModel.markAsSkipped(video)
        }
    }

    private func handleGoToChannel(_ channelId: String) {
        selectedChannelId = channelId
    }

    private func promptMarkAllWatched() {
        markAllWatchedVideoIds = feedViewModel.filteredVideos
            .filter { $0.status != .watched }
            .map(\.id)
        showingMarkAllWatchedConfirmation = true
    }

    private func confirmMarkAllWatched() {
        let ids = markAllWatchedVideoIds
        markAllWatchedVideoIds = []
        Task {
            await feedViewModel.markVideosAsWatched(videoIds: ids)
        }
    }

    private func cancelMarkAllWatched() {
        markAllWatchedVideoIds = []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FeedMainContentView(
                    onVideoTap: handleVideoTap,
                    onToggleWatched: handleToggleWatched,
                    onMarkSkipped: handleMarkSkipped,
                    onGoToChannel: handleGoToChannel
                )
                
                // Overlay loading indicator when refreshing with existing data
                if feedViewModel.loadingState.isLoading && !feedViewModel.allVideos.isEmpty {
                    VStack {
                        RefreshIndicatorView(loadingState: feedViewModel.loadingState)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Feed")
            .searchable(text: $feedViewModel.searchText, prompt: "Search videos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    FeedToolbarMenuView(onMarkAllWatched: promptMarkAllWatched)
                }
            }
            .refreshable {
                await feedViewModel.refresh()
            }
            .task {
                if feedViewModel.allVideos.isEmpty {
                    await feedViewModel.refresh(forceFull: true)
                }
            }
            .onChange(of: feedViewModel.error) { _, newError in
                showingError = newError != nil
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    feedViewModel.clearError()
                }
            } message: {
                Text(feedViewModel.error ?? "Unknown error")
            }
            .confirmationDialog(
                "Mark all watched?",
                isPresented: $showingMarkAllWatchedConfirmation,
                titleVisibility: .visible
            ) {
                Button("Mark all watched") { confirmMarkAllWatched() }
                Button("Cancel", role: .cancel) {
                    cancelMarkAllWatched()
                }
            } message: {
                Text("This will mark \(markAllWatchedVideoIds.count) videos as watched.")
            }
            .fullScreenCover(item: $selectedVideo) { video in
                FeedVideoPlayerCoverView(
                    video: video,
                    selectedVideo: $selectedVideo,
                    selectedChannelId: $selectedChannelId
                )
            }
            // Navigation to channel when "Go to Channel" is tapped
            .navigationDestination(isPresented: Binding(
                get: { selectedChannelId != nil },
                set: { if !$0 { selectedChannelId = nil } }
            )) {
                channelDestinationView
            }
        }
    }
    
    /// Destination view for channel navigation
    @ViewBuilder
    private var channelDestinationView: some View {
        if let channelId = selectedChannelId,
           let channel = feedViewModel.channels.first(where: { $0.id == channelId }) {
            ChannelDetailView(channel: channel)
        } else {
            Text("Channel not found")
        }
    }
}

private struct FeedToolbarMenuView: View {
    @EnvironmentObject var feedViewModel: FeedViewModel
    let onMarkAllWatched: () -> Void

    var body: some View {
        let allFilteredWatched = feedViewModel.filteredVideos.allSatisfy { $0.status == .watched }

        Menu {
            Section("Filter") {
                Button(action: { feedViewModel.selectedStatus = .unwatched }) {
                    if feedViewModel.selectedStatus == .unwatched {
                        Label("Unwatched", systemImage: "checkmark")
                    } else {
                        Text("Unwatched")
                    }
                }

                Button(action: { feedViewModel.selectedStatus = nil }) {
                    if feedViewModel.selectedStatus == nil {
                        Label("All Videos", systemImage: "checkmark")
                    } else {
                        Text("All Videos")
                    }
                }

                Button(action: { feedViewModel.selectedStatus = .watched }) {
                    if feedViewModel.selectedStatus == .watched {
                        Label("Watched", systemImage: "checkmark")
                    } else {
                        Text("Watched")
                    }
                }

                Button(action: { feedViewModel.selectedStatus = .skipped }) {
                    if feedViewModel.selectedStatus == .skipped {
                        Label("Skipped", systemImage: "checkmark")
                    } else {
                        Text("Skipped")
                    }
                }
            }

            Section("Refresh") {
                Button(action: { Task { await feedViewModel.refresh() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise.circle")
                }

                Button(action: { Task { await feedViewModel.resetAndRefresh() } }) {
                    Label("Reload All", systemImage: "arrow.counterclockwise")
                }
            }

            Section("Actions") {
                Button(action: onMarkAllWatched) {
                    Label("Mark all watched", systemImage: "checkmark.circle")
                }
                .disabled(allFilteredWatched)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
}

private struct FeedMainContentView: View {
    @EnvironmentObject var feedViewModel: FeedViewModel

    let onVideoTap: (Video) -> Void
    let onToggleWatched: (Video) -> Void
    let onMarkSkipped: (Video) -> Void
    let onGoToChannel: (String) -> Void

    var body: some View {
        if feedViewModel.loadingState.isLoading && feedViewModel.allVideos.isEmpty {
            DetailedLoadingView(loadingState: feedViewModel.loadingState)
        } else if feedViewModel.filteredVideos.isEmpty {
            EmptyFeedView(
                hasVideos: !feedViewModel.allVideos.isEmpty,
                searchText: feedViewModel.searchText
            )
        } else {
            VideoListView(
                videos: feedViewModel.filteredVideos,
                onVideoTap: onVideoTap,
                onToggleWatched: onToggleWatched,
                onMarkSkipped: onMarkSkipped,
                onGoToChannel: onGoToChannel
            )
        }
    }
}

private struct FeedVideoPlayerCoverView: View {
    let video: Video
    @EnvironmentObject var feedViewModel: FeedViewModel
    @Binding var selectedVideo: Video?
    @Binding var selectedChannelId: String?

    var body: some View {
        let _ = appLog("fullScreenCover presenting video: \(video.id)", category: .ui, level: .info)
        let nextVideo = getNextVideo(after: video)
        let previousVideo = getPreviousVideo(before: video)
        let videoIndex = getVideoIndex(for: video)

        VideoPlayerView(
            video: video,
            onDismiss: {
                appLog("VideoPlayerView onDismiss called", category: .ui, level: .info)
                selectedVideo = nil
            },
            onMarkWatched: {
                appLog("VideoPlayerView onMarkWatched called", category: .ui, level: .info)
                Task {
                    await feedViewModel.markAsWatched(video)
                }
            },
            onMarkSkipped: {
                appLog("VideoPlayerView onMarkSkipped called", category: .ui, level: .info)
                Task {
                    await feedViewModel.markAsSkipped(video)
                }
            },
            onGoToChannel: { channelId in
                appLog("VideoPlayerView onGoToChannel called: \(channelId)", category: .ui, level: .info)
                selectedVideo = nil
                selectedChannelId = channelId
            },
            nextVideo: nextVideo,
            previousVideo: previousVideo,
            onNextVideo: { next in
                appLog("VideoPlayerView onNextVideo called: \(next.id)", category: .ui, level: .info)
                selectedVideo = next
            },
            onPreviousVideo: { previous in
                appLog("VideoPlayerView onPreviousVideo called: \(previous.id)", category: .ui, level: .info)
                selectedVideo = previous
            },
            currentIndex: videoIndex,
            totalVideos: feedViewModel.filteredVideos.count,
            savedPosition: feedViewModel.getPlaybackPosition(for: video.id),
            onSavePosition: { position in
                feedViewModel.savePlaybackPosition(for: video.id, position: position)
            }
        )
    }

    private func getVideoIndex(for video: Video) -> Int? {
        let videos = feedViewModel.filteredVideos
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        return index + 1 // Convert to 1-based index
    }

    private func getNextVideo(after video: Video) -> Video? {
        let videos = feedViewModel.filteredVideos
        guard let currentIndex = videos.firstIndex(where: { $0.id == video.id }) else {
            return videos.first
        }
        let nextIndex = currentIndex + 1
        return nextIndex < videos.count ? videos[nextIndex] : nil
    }

    private func getPreviousVideo(before video: Video) -> Video? {
        let videos = feedViewModel.filteredVideos
        guard let currentIndex = videos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        let previousIndex = currentIndex - 1
        return previousIndex >= 0 ? videos[previousIndex] : nil
    }
}

// MARK: - Detailed Loading View

struct DetailedLoadingView: View {
    let loadingState: LoadingState
    
    var body: some View {
        VStack(spacing: 24) {
            // Animated loading indicator
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(Angle(degrees: loadingRotation))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: loadingRotation)
            }
            .onAppear {
                loadingRotation = 360
            }
            
            VStack(spacing: 8) {
                Text(loadingTitle)
                    .font(.headline)
                
                Text(loadingState.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
    
    @State private var loadingRotation: Double = 0
    
    private var loadingTitle: String {
        switch loadingState {
        case .refreshing:
            return "Refreshing"
        default:
            return "Loading"
        }
    }
}

// MARK: - Refresh Indicator View

struct RefreshIndicatorView: View {
    let loadingState: LoadingState
    
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text(loadingState.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.top, 8)
    }
}

// MARK: - Empty Feed View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your feed...")
                .foregroundColor(.secondary)
        }
    }
}

struct EmptyFeedView: View {
    let hasVideos: Bool
    let searchText: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: hasVideos ? "magnifyingglass" : "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            if hasVideos {
                Text("No videos match '\(searchText)'")
                    .font(.headline)
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("You're all caught up!")
                    .font(.headline)
                Text("Pull to refresh for new videos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct VideoListView: View {
    let videos: [Video]
    let onVideoTap: (Video) -> Void
    let onToggleWatched: (Video) -> Void
    let onMarkSkipped: (Video) -> Void
    let onGoToChannel: ((String) -> Void)?

    init(
        videos: [Video],
        onVideoTap: @escaping (Video) -> Void,
        onToggleWatched: @escaping (Video) -> Void,
        onMarkSkipped: @escaping (Video) -> Void,
        onGoToChannel: ((String) -> Void)? = nil
    ) {
        self.videos = videos
        self.onVideoTap = onVideoTap
        self.onToggleWatched = onToggleWatched
        self.onMarkSkipped = onMarkSkipped
        self.onGoToChannel = onGoToChannel
    }
    
    var body: some View {
        List {
            ForEach(videos) { video in
                VideoRowView(video: video)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appLog("Video row tapped: \(video.title)", category: .ui, level: .info, context: [
                            "videoId": video.id,
                            "channelName": video.channelName,
                            "thumbnailURL": video.thumbnailURL?.absoluteString ?? "nil"
                        ])
                        onVideoTap(video)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onMarkSkipped(video)
                        } label: {
                            Label("Skip", systemImage: "forward.fill")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            // Toggle between watched and unwatched
                            onToggleWatched(video)
                        } label: {
                            if video.status == .watched {
                                Label("Unwatch", systemImage: "arrow.uturn.backward")
                            } else {
                                Label("Watched", systemImage: "checkmark")
                            }
                        }
                        .tint(video.status == .watched ? .gray : .green)
                    }
                    .contextMenu {
                        Button {
                            onToggleWatched(video)
                        } label: {
                            if video.status == .watched {
                                Label("Mark as Unwatched", systemImage: "arrow.uturn.backward.circle")
                            } else {
                                Label("Mark as Watched", systemImage: "checkmark.circle")
                            }
                        }
                        
                        Button {
                            onMarkSkipped(video)
                        } label: {
                            Label("Skip Video", systemImage: "forward.fill")
                        }

                        if let onGoToChannel {
                            Button {
                                onGoToChannel(video.channelId)
                            } label: {
                                Label("Go to Channel", systemImage: "person.circle")
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    // Create a temporary in-memory ModelContext for preview
    let schema = Schema([StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let viewModel = FeedViewModel(modelContext: context)
    
    FeedView()
        .environmentObject(viewModel)
}
#endif // os(iOS)
