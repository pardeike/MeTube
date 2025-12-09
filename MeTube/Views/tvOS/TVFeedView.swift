//
//  TVFeedView.swift
//  MeTube
//
//  tvOS-specific feed view with grid layout and focus navigation
//

import SwiftUI
import SwiftData

#if os(tvOS)
struct TVFeedView: View {
    @EnvironmentObject var feedViewModel: FeedViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedVideo: Video?
    @State private var showingError = false
    @FocusState private var focusedVideoId: String?
    
    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 40)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                if feedViewModel.loadingState.isLoading && feedViewModel.allVideos.isEmpty {
                    TVLoadingView(loadingState: feedViewModel.loadingState)
                } else if feedViewModel.filteredVideos.isEmpty {
                    TVEmptyFeedView(
                        hasVideos: !feedViewModel.allVideos.isEmpty,
                        searchText: feedViewModel.searchText
                    )
                } else {
                    videoGridView
                }
                
                // Loading indicator when refreshing with existing content
                if feedViewModel.loadingState.isLoading && !feedViewModel.allVideos.isEmpty {
                    VStack {
                        HStack {
                            Spacer()
                            TVRefreshIndicator(loadingState: feedViewModel.loadingState)
                                .padding()
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    TVFilterMenu(
                        selectedStatus: $feedViewModel.selectedStatus,
                        onRefresh: {
                            Task {
                                if let token = await authManager.getAccessToken() {
                                    await feedViewModel.forceFullRefresh(accessToken: token)
                                }
                            }
                        }
                    )
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        authManager.signOut()
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
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
                    totalVideos: feedViewModel.filteredVideos.count,
                    savedPosition: feedViewModel.getPlaybackPosition(for: video.id),
                    onSavePosition: { position in
                        feedViewModel.savePlaybackPosition(for: video.id, position: position)
                    }
                )
            }
        }
    }
    
    // MARK: - Video Grid
    
    @ViewBuilder
    private var videoGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(feedViewModel.filteredVideos) { video in
                    Button(action: {
                        selectedVideo = video
                    }) {
                        TVVideoCardView(video: video)
                    }
                    .buttonStyle(.card)
                    .focused($focusedVideoId, equals: video.id)
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
    
    // MARK: - Navigation Helpers
    
    private func getVideoIndex(for video: Video) -> Int? {
        guard let index = feedViewModel.filteredVideos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        return index + 1
    }
    
    private func getNextVideo(after video: Video) -> Video? {
        guard let currentIndex = feedViewModel.filteredVideos.firstIndex(where: { $0.id == video.id }) else {
            return feedViewModel.filteredVideos.first
        }
        let nextIndex = currentIndex + 1
        return nextIndex < feedViewModel.filteredVideos.count ? feedViewModel.filteredVideos[nextIndex] : nil
    }
    
    private func getPreviousVideo(before video: Video) -> Video? {
        guard let currentIndex = feedViewModel.filteredVideos.firstIndex(where: { $0.id == video.id }) else {
            return nil
        }
        let previousIndex = currentIndex - 1
        return previousIndex >= 0 ? feedViewModel.filteredVideos[previousIndex] : nil
    }
}

// MARK: - Supporting Views

struct TVLoadingView: View {
    let loadingState: LoadingState
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(Angle(degrees: rotation))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotation)
            }
            .onAppear {
                rotation = 360
            }
            
            Text(loadingState.description)
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}

struct TVEmptyFeedView: View {
    let hasVideos: Bool
    let searchText: String
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: hasVideos ? "magnifyingglass" : "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.secondary)
            
            if hasVideos {
                Text("No videos match '\(searchText)'")
                    .font(.title)
                Text("Try a different search term")
                    .font(.title3)
                    .foregroundColor(.secondary)
            } else {
                Text("You're all caught up!")
                    .font(.title)
                Text("Check back later for new videos")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TVRefreshIndicator: View {
    let loadingState: LoadingState
    
    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
            Text(loadingState.description)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct TVFilterMenu: View {
    @Binding var selectedStatus: VideoStatus?
    let onRefresh: () -> Void
    
    var body: some View {
        Menu {
            Section("Filter") {
                Button(action: { selectedStatus = .unwatched }) {
                    if selectedStatus == .unwatched {
                        Label("Unwatched", systemImage: "checkmark")
                    } else {
                        Text("Unwatched")
                    }
                }
                
                Button(action: { selectedStatus = nil }) {
                    if selectedStatus == nil {
                        Label("All Videos", systemImage: "checkmark")
                    } else {
                        Text("All Videos")
                    }
                }
                
                Button(action: { selectedStatus = .watched }) {
                    if selectedStatus == .watched {
                        Label("Watched", systemImage: "checkmark")
                    } else {
                        Text("Watched")
                    }
                }
            }
            
            Section("Refresh") {
                Button(action: onRefresh) {
                    Label("Full Refresh", systemImage: "arrow.clockwise.circle")
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

#Preview {
    let schema = Schema([VideoEntity.self, ChannelEntity.self, StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let viewModel = FeedViewModel(modelContext: context)
    
    return TVFeedView()
        .environmentObject(AuthenticationManager())
        .environmentObject(viewModel)
}
#endif
