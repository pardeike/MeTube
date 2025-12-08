//
//  ContentView.swift
//  MeTube
//
//  Main content view with tab navigation
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var feedViewModel: FeedViewModel
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            authManager.checkAuthenticationStatus()
        }
    }
}

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

#Preview {
    // Create a temporary in-memory ModelContext for preview
    let schema = Schema([VideoEntity.self, ChannelEntity.self, StatusEntity.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let viewModel = FeedViewModel(modelContext: context)
    
    return ContentView()
        .environmentObject(AuthenticationManager())
        .environmentObject(viewModel)
}
