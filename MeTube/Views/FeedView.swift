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
    @State private var showingPlayer = false
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            Group {
                if feedViewModel.isLoading && feedViewModel.allVideos.isEmpty {
                    LoadingView()
                } else if feedViewModel.filteredVideos.isEmpty {
                    EmptyFeedView(
                        hasVideos: !feedViewModel.allVideos.isEmpty,
                        searchText: feedViewModel.searchText
                    )
                } else {
                    VideoListView(
                        videos: feedViewModel.filteredVideos,
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
            .navigationTitle("Feed")
            .searchable(text: $feedViewModel.searchText, prompt: "Search videos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            feedViewModel.selectedStatus = .unwatched
                        }) {
                            Label("Unwatched", systemImage: feedViewModel.selectedStatus == .unwatched ? "checkmark" : "")
                        }
                        
                        Button(action: {
                            feedViewModel.selectedStatus = nil
                        }) {
                            Label("All Videos", systemImage: feedViewModel.selectedStatus == nil ? "checkmark" : "")
                        }
                        
                        Button(action: {
                            feedViewModel.selectedStatus = .watched
                        }) {
                            Label("Watched", systemImage: feedViewModel.selectedStatus == .watched ? "checkmark" : "")
                        }
                        
                        Button(action: {
                            feedViewModel.selectedStatus = .skipped
                        }) {
                            Label("Skipped", systemImage: feedViewModel.selectedStatus == .skipped ? "checkmark" : "")
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
            .fullScreenCover(isPresented: $showingPlayer) {
                if let video = selectedVideo {
                    VideoPlayerView(video: video, onDismiss: {
                        showingPlayer = false
                    }, onMarkWatched: {
                        Task {
                            await feedViewModel.markAsWatched(video)
                        }
                    })
                }
            }
        }
    }
}

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
