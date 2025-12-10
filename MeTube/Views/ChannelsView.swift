//
//  ChannelsView.swift
//  MeTube
//
//  View showing all subscribed channels
//  Note: iOS only - tvOS uses TVChannelsView
//

import SwiftUI
import SwiftData

// ChannelFilter enum is defined in SharedTypes.swift

#if os(iOS)

struct ChannelsView: View {
    @EnvironmentObject var feedViewModel: FeedViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var searchText: String = ""
    @State private var selectedFilter: ChannelFilter = .withUnseenVideos
    
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
    
    var body: some View {
        NavigationView {
            Group {
                if feedViewModel.isLoading && feedViewModel.channels.isEmpty {
                    LoadingView()
                } else if filteredChannels.isEmpty {
                    EmptyChannelsView(hasChannels: !feedViewModel.channels.isEmpty)
                } else {
                    ChannelListView(channels: filteredChannels, feedViewModel: feedViewModel)
                }
            }
            .navigationTitle("Channels")
            .searchable(text: $searchText, prompt: "Search channels")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Filter") {
                            Button(action: {
                                selectedFilter = .all
                            }) {
                                if selectedFilter == .all {
                                    Label("All Channels", systemImage: "checkmark")
                                } else {
                                    Text("All Channels")
                                }
                            }
                            
                            Button(action: {
                                selectedFilter = .withUnseenVideos
                            }) {
                                if selectedFilter == .withUnseenVideos {
                                    Label("With Unseen Videos", systemImage: "checkmark")
                                } else {
                                    Text("With Unseen Videos")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                if let token = await authManager.getAccessToken() {
                    await feedViewModel.refreshFeed(accessToken: token)
                }
            }
        }
    }
}

struct EmptyChannelsView: View {
    let hasChannels: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            if hasChannels {
                Text("No channels match your search")
                    .font(.headline)
            } else {
                Text("No subscriptions found")
                    .font(.headline)
                Text("Make sure you're subscribed to channels on YouTube")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

struct ChannelListView: View {
    let channels: [Channel]
    @ObservedObject var feedViewModel: FeedViewModel
    
    var body: some View {
        List {
            ForEach(channels) { channel in
                NavigationLink(destination: ChannelDetailView(channel: channel)) {
                    ChannelRowView(
                        channel: channel,
                        unwatchedCount: feedViewModel.unwatchedCount(for: channel.id)
                    )
                }
            }
        }
        .listStyle(.plain)
    }
}

struct ChannelRowView: View {
    let channel: Channel
    let unwatchedCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Channel Thumbnail
            AsyncImage(url: channel.thumbnailURL) { phase in
                switch phase {
                case .empty:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                case .failure:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                @unknown default:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(1)
                
                if let description = channel.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Unwatched Badge
            if unwatchedCount > 0 {
                Text("\(unwatchedCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    // Create a temporary in-memory ModelContext for preview
    let schema = Schema([VideoEntity.self, ChannelEntity.self, StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let viewModel = FeedViewModel(modelContext: context)
    
    return ChannelsView()
        .environmentObject(viewModel)
        .environmentObject(AuthenticationManager())
}
#endif // os(iOS)
