//
//  MeTubeApp.swift
//  MeTube
//
//  A distraction-free YouTube subscription feed app
//

import SwiftUI

@main
struct MeTubeApp: App {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var feedViewModel = FeedViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(feedViewModel)
        }
    }
}
