//
//  ContentView.swift
//  MeTube
//
//  Main content view with tab navigation
//  Handles both iOS and tvOS platforms
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var feedViewModel: FeedViewModel
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                #if os(tvOS)
                TVMainTabView()
                #else
                MainTabView()
                #endif
            } else {
                #if os(tvOS)
                TVLoginView()
                #else
                LoginView()
                #endif
            }
        }
        .onAppear {
            // Set the auth manager reference for cross-device hub user ID
            feedViewModel.setAuthManager(authManager)
            authManager.checkAuthenticationStatus()
        }
    }
}

// MARK: - iOS Main Tab View

#if os(iOS)
struct MainTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "play.rectangle.fill")
                }
            
            ChannelsView()
                .tabItem {
                    Label("Channels", systemImage: "person.3.fill")
                }
        }
    }
}
#endif

// MARK: - Notifications

#if os(tvOS)
extension Notification.Name {
    static let tvFeedRequestRefresh = Notification.Name("tvFeedRequestRefresh")
}
#endif
// MARK: - tvOS Main Tab View

#if os(tvOS)
struct TVMainTabView: View {
    enum TVTab: CaseIterable {
        case feed
        case channels
        
        var label: String {
            switch self {
            case .feed: return "Feed"
            case .channels: return "Channels"
            }
        }
        
        var systemImage: String {
            switch self {
            case .feed: return "play.rectangle.fill"
            case .channels: return "person.3.fill"
            }
        }
    }
    
    @State private var selectedTab: TVTab = .feed
    @State private var channelFilter: ChannelFilter = .withUnseenVideos
    @State private var channelSearchText: String = ""
    @State private var channelIsEditingSearch: Bool = false
    @State private var feedStatusFilter: VideoStatus? = .unwatched
    @State private var feedSearchText: String = ""
    @State private var feedIsEditingSearch: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            headerRow
            
            Group {
                switch selectedTab {
                case .feed:
                    TVFeedView(
                        selectedStatus: $feedStatusFilter,
                        searchText: $feedSearchText,
                        isEditingSearch: $feedIsEditingSearch
                    )
                case .channels:
                    TVChannelsView(
                        selectedFilter: $channelFilter,
                        searchText: $channelSearchText,
                        isEditingSearch: $channelIsEditingSearch
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var headerRow: some View {
        HStack(spacing: 16) {
            segmentedControl
            
            Spacer()
            
            if selectedTab == .channels {
                Menu {
                    Section("Filter") {
                        Button(action: { channelFilter = .all }) {
                            if channelFilter == .all {
                                Label("All Channels", systemImage: "checkmark")
                            } else {
                                Text("All Channels")
                            }
                        }
                        
                        Button(action: { channelFilter = .withUnseenVideos }) {
                            if channelFilter == .withUnseenVideos {
                                Label("With Unseen Videos", systemImage: "checkmark")
                            } else {
                                Text("With Unseen Videos")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                        .padding(8)
                        .background(
                            Circle().fill(Color.white.opacity(0.08))
                        )
                }
                
                Button {
                    if channelIsEditingSearch {
                        // Hide field but keep query active
                        channelIsEditingSearch = false
                    } else if !channelSearchText.isEmpty {
                        // Clear active search
                        channelSearchText = ""
                        channelIsEditingSearch = false
                    } else {
                        // Start editing
                        channelIsEditingSearch = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .imageScale(.large)
                        .foregroundColor((channelIsEditingSearch || !channelSearchText.isEmpty) ? .accentColor : .primary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill((channelIsEditingSearch || !channelSearchText.isEmpty) ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
            } else if selectedTab == .feed {
                Menu {
                    Section("Filter") {
                        Button(action: { feedStatusFilter = .unwatched }) {
                            if feedStatusFilter == .unwatched {
                                Label("Unwatched", systemImage: "checkmark")
                            } else {
                                Text("Unwatched")
                            }
                        }
                        
                        Button(action: { feedStatusFilter = nil }) {
                            if feedStatusFilter == nil {
                                Label("All Videos", systemImage: "checkmark")
                            } else {
                                Text("All Videos")
                            }
                        }
                        
                        Button(action: { feedStatusFilter = .watched }) {
                            if feedStatusFilter == .watched {
                                Label("Watched", systemImage: "checkmark")
                            } else {
                                Text("Watched")
                            }
                        }
                    }
                    
                    Section("Refresh") {
                        Button("Full Refresh") {
                            NotificationCenter.default.post(name: .tvFeedRequestRefresh, object: nil)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                        .padding(8)
                        .background(
                            Circle().fill(Color.white.opacity(0.08))
                        )
                }
                
                Button {
                    if feedIsEditingSearch {
                        feedIsEditingSearch = false
                    } else if !feedSearchText.isEmpty {
                        feedSearchText = ""
                        feedIsEditingSearch = false
                    } else {
                        feedIsEditingSearch = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .imageScale(.large)
                        .foregroundColor((feedIsEditingSearch || !feedSearchText.isEmpty) ? .accentColor : .primary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill((feedIsEditingSearch || !feedSearchText.isEmpty) ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
    }
    
    private var segmentedControl: some View {
        HStack(spacing: 10) {
            ForEach(TVTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    // Reset inline search UI when switching away
                    if tab != .channels {
                        channelIsEditingSearch = false
                        channelSearchText = ""
                    }
                    if tab != .feed {
                        feedIsEditingSearch = false
                        feedSearchText = ""
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage)
                            .imageScale(.medium)
                        Text(tab.label)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(selectedTab == tab ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
        )
    }
}
#endif

#Preview {
    // Create a temporary in-memory ModelContext for preview
    let schema = Schema([VideoEntity.self, ChannelEntity.self, StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let authManager = AuthenticationManager()
    let viewModel = FeedViewModel(modelContext: context, authManager: authManager)
    
    return ContentView()
        .environmentObject(authManager)
        .environmentObject(viewModel)
}
