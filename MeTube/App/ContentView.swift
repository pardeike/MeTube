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

// MARK: - tvOS Main Tab View

#if os(tvOS)
struct TVMainTabView: View {
    var body: some View {
        TabView {
            TVFeedView()
                .tabItem {
                    Label("Feed", systemImage: "play.rectangle.fill")
                }
            
            TVChannelsView()
                .tabItem {
                    Label("Channels", systemImage: "person.3.fill")
                }
        }
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
