//
//  FeedView.swift
//  MeTube
//
//  Main subscription feed view showing unwatched videos
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var feedViewModel: FeedViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedVideo: Video?
    @State private var showingError = false
    @State private var showingQuotaInfo = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Group {
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
                            onVideoTap: { video in
                                appLog("Selecting video for playback: \(video.title)", category: .ui, level: .info, context: [
                                    "videoId": video.id,
                                    "duration": video.duration
                                ])
                                selectedVideo = video
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
                    Menu {
                        Section("Filter") {
                            Button(action: {
                                feedViewModel.selectedStatus = .unwatched
                            }) {
                                if feedViewModel.selectedStatus == .unwatched {
                                    Label("Unwatched", systemImage: "checkmark")
                                } else {
                                    Text("Unwatched")
                                }
                            }
                            
                            Button(action: {
                                feedViewModel.selectedStatus = nil
                            }) {
                                if feedViewModel.selectedStatus == nil {
                                    Label("All Videos", systemImage: "checkmark")
                                } else {
                                    Text("All Videos")
                                }
                            }
                            
                            Button(action: {
                                feedViewModel.selectedStatus = .watched
                            }) {
                                if feedViewModel.selectedStatus == .watched {
                                    Label("Watched", systemImage: "checkmark")
                                } else {
                                    Text("Watched")
                                }
                            }
                            
                            Button(action: {
                                feedViewModel.selectedStatus = .skipped
                            }) {
                                if feedViewModel.selectedStatus == .skipped {
                                    Label("Skipped", systemImage: "checkmark")
                                } else {
                                    Text("Skipped")
                                }
                            }
                        }
                        
                        Section("Refresh") {
                            Button(action: {
                                Task {
                                    if let token = await authManager.getAccessToken() {
                                        await feedViewModel.forceFullRefresh(accessToken: token)
                                    }
                                }
                            }) {
                                Label("Full Refresh", systemImage: "arrow.clockwise.circle")
                            }
                        }
                        
                        Section("Info") {
                            Button(action: {
                                showingQuotaInfo = true
                            }) {
                                Label("API Quota: \(feedViewModel.quotaInfo.remainingQuota)", systemImage: quotaIcon)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        authManager.signOut()
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .refreshable {
                if let token = await authManager.getAccessToken() {
                    await feedViewModel.refreshFeed(accessToken: token)
                }
            }
            .task {
                if feedViewModel.allVideos.isEmpty {
                    if let token = await authManager.getAccessToken() {
                        await feedViewModel.refreshFeed(accessToken: token)
                    }
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
            .sheet(isPresented: $showingQuotaInfo) {
                QuotaInfoView(quotaInfo: feedViewModel.quotaInfo, lastRefresh: feedViewModel.lastRefreshDate)
            }
            .fullScreenCover(item: $selectedVideo) { video in
                let _ = appLog("fullScreenCover presenting video: \(video.id)", category: .ui, level: .info)
                let nextVideo = getNextVideo(after: video)
                let previousVideo = getPreviousVideo(before: video)
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
                    nextVideo: nextVideo,
                    previousVideo: previousVideo,
                    onNextVideo: { next in
                        appLog("VideoPlayerView onNextVideo called: \(next.id)", category: .ui, level: .info)
                        selectedVideo = next
                    },
                    onPreviousVideo: { previous in
                        appLog("VideoPlayerView onPreviousVideo called: \(previous.id)", category: .ui, level: .info)
                        selectedVideo = previous
                    }
                )
            }
        }
    }
    
    /// Gets the next unwatched video after the current one
    private func getNextVideo(after video: Video) -> Video? {
        let videos = feedViewModel.filteredVideos
        guard let currentIndex = videos.firstIndex(where: { $0.id == video.id }) else {
            return videos.first
        }
        let nextIndex = currentIndex + 1
        return nextIndex < videos.count ? videos[nextIndex] : nil
    }
    
    /// Gets the previous video before the current one
    private func getPreviousVideo(before video: Video) -> Video? {
        let videos = feedViewModel.filteredVideos
        guard let currentIndex = videos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        let previousIndex = currentIndex - 1
        return previousIndex >= 0 ? videos[previousIndex] : nil
    }
    
    private var quotaIcon: String {
        if feedViewModel.quotaInfo.isExceeded {
            return "exclamationmark.triangle.fill"
        } else if feedViewModel.quotaInfo.isWarning {
            return "exclamationmark.circle"
        } else {
            return "chart.bar"
        }
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
            
            // Progress bar for video loading
            if case .loadingVideos(let index, let total, _) = loadingState {
                VStack(spacing: 4) {
                    ProgressView(value: Double(index), total: Double(total))
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    
                    Text("\(index) of \(total) channels")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    @State private var loadingRotation: Double = 0
    
    private var loadingTitle: String {
        switch loadingState {
        case .loadingSubscriptions:
            return "Fetching Subscriptions"
        case .loadingVideos:
            return "Loading Videos"
        case .loadingStatuses:
            return "Syncing Status"
        case .refreshing:
            return "Checking for Updates"
        case .backgroundRefreshing:
            return "Background Update"
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

// MARK: - Quota Info View

struct QuotaInfoView: View {
    let quotaInfo: QuotaInfo
    let lastRefresh: Date?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("API Usage Today") {
                    HStack {
                        Text("Used")
                        Spacer()
                        Text("\(quotaInfo.usedToday) units")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Remaining")
                        Spacer()
                        Text("\(quotaInfo.remainingQuota) units")
                            .foregroundColor(quotaInfo.isWarning ? .orange : .secondary)
                    }
                    
                    HStack {
                        Text("Daily Limit")
                        Spacer()
                        Text("\(FeedConfig.dailyQuotaLimit) units")
                            .foregroundColor(.secondary)
                    }
                    
                    // Progress bar
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(quotaInfo.usedToday), total: Double(FeedConfig.dailyQuotaLimit))
                            .progressViewStyle(.linear)
                            .tint(quotaInfo.isExceeded ? .red : (quotaInfo.isWarning ? .orange : .blue))
                        
                        Text(String(format: "%.1f%% used", quotaInfo.percentUsed))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Quota Reset") {
                    HStack {
                        Text("Resets at")
                        Spacer()
                        Text("Midnight Pacific Time")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Last Refresh") {
                    if let lastRefresh = lastRefresh {
                        HStack {
                            Text("Time")
                            Spacer()
                            Text(lastRefresh, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Not yet refreshed")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(footer: Text("The YouTube API has a daily quota of 10,000 units. Each refresh uses approximately 1-5 units per channel. Quota resets at midnight Pacific Time.")) {
                    EmptyView()
                }
            }
            .navigationTitle("API Quota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
    let onMarkWatched: (Video) -> Void
    let onMarkSkipped: (Video) -> Void
    
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
                            onMarkWatched(video)
                        } label: {
                            Label("Watched", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button {
                            onMarkWatched(video)
                        } label: {
                            Label("Mark as Watched", systemImage: "checkmark.circle")
                        }
                        
                        Button {
                            onMarkSkipped(video)
                        } label: {
                            Label("Skip Video", systemImage: "forward.fill")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    FeedView()
        .environmentObject(FeedViewModel())
        .environmentObject(AuthenticationManager())
}
