# MeTube

A distraction-free YouTube subscription feed app for iOS built with SwiftUI.

## Overview

MeTube is designed as a distraction-free YouTube client focused solely on subscribed channel content. The goal is to eliminate YouTube's algorithmic recommendations, Shorts feeds, and other distractions by providing only the videos from channels you subscribe to.

## Features

- **Chronological Subscription Feed**: Display new videos from subscribed channels in time-sorted order
- **No Shorts**: Automatically filters out YouTube Shorts (videos under 60 seconds)
- **Watch Status Tracking**: Mark videos as watched, skipped, or unwatched
- **Channel Browsing**: View all subscribed channels with unseen video counts
- **Search & Filter**: Quickly find videos by title or channel name
- **AirPlay Support**: Stream videos to Apple TV
- **CloudKit Sync**: Watch status syncs across all your devices via iCloud

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Google Cloud Console project with YouTube Data API v3 enabled
- Apple Developer account (for CloudKit)

## Setup

### 1. Google Cloud Console Configuration

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project or select an existing one
3. Enable the **YouTube Data API v3**
4. Go to **Credentials** and create an **OAuth 2.0 Client ID**
   - Application type: iOS
   - Bundle ID: `com.metube.app`
5. Download the credentials

### 2. Xcode Project Configuration

1. Open `MeTube.xcodeproj` in Xcode
2. Select the MeTube target
3. Go to **Signing & Capabilities**
4. Select your Development Team
5. Update the Bundle Identifier if needed
6. Ensure **iCloud** capability is enabled with **CloudKit**

### 3. Running the App

1. Build and run on your device or simulator
2. On first launch, tap **Configure OAuth** to enter your Google Client ID
3. Tap **Sign in with Google** to authenticate
4. The app will fetch your YouTube subscriptions and display videos

## Architecture

The app follows MVVM (Model-View-ViewModel) architecture with a hub server for efficient data fetching:

```
MeTube/
├── App/
│   ├── MeTubeApp.swift        # App entry point
│   └── ContentView.swift       # Main navigation
├── Models/
│   ├── Channel.swift           # Channel model with CloudKit support
│   ├── Video.swift             # Video model with status tracking
│   └── YouTubeAPIModels.swift  # API response models
├── ViewModels/
│   ├── FeedViewModel.swift     # Feed and status management
│   └── PlayerViewModel.swift   # Video playback state
├── Views/
│   ├── LoginView.swift         # Authentication UI
│   ├── FeedView.swift          # Main feed list
│   ├── ChannelsView.swift      # Channels list
│   ├── ChannelDetailView.swift # Single channel videos
│   ├── VideoPlayerView.swift   # Video player with AirPlay
│   └── Components/
│       └── VideoRowView.swift  # Video list item
└── Services/
    ├── HubServerService.swift     # MeTube Hub Server client
    ├── YouTubeService.swift       # YouTube API client (subscriptions only)
    ├── CloudKitService.swift      # CloudKit operations
    └── AuthenticationManager.swift # OAuth handling
```

## Data Flow

1. **Authentication**: OAuth 2.0 flow with Google for YouTube API access
2. **Subscriptions**: Fetches subscribed channels via YouTube Data API
3. **Channel Registration**: Registers user's channels with MeTube Hub Server
4. **Videos**: Fetches aggregated video feed from Hub Server (no direct API calls per channel)
5. **Status Sync**: Watch/skip status stored in CloudKit private database
6. **Playback**: Videos embedded via YouTube iframe with AirPlay support

## Hub Server Integration

The app uses the [MeTube Hub Server](https://github.com/pardeike/MeTubeServer) to minimize YouTube API quota usage:
- Server subscribes to YouTube WebSub for real-time updates
- Shared video cache across all users
- App only fetches subscriptions from YouTube (~2-3 API calls)
- All video metadata comes from the hub server (0 API calls)

See [SERVER_INTEGRATION.md](SERVER_INTEGRATION.md) for technical details.

## Privacy

- All data is stored in your private iCloud database
- No analytics or external tracking
- OAuth tokens stored securely in iOS Keychain
- Videos play through official YouTube embed

## API Quota

With the hub server integration, YouTube API quota usage is minimal:
- **Before**: 100+ API calls per refresh (1 per channel + video details)
- **After**: 2-3 API calls per refresh (only for fetching subscriptions)
- Hub server handles all video fetching with YouTube WebSub push notifications
- See [SERVER_INTEGRATION.md](SERVER_INTEGRATION.md) for architecture details

## License

This is a personal project not intended for App Store distribution.

## Contributing

This is designed as a personal-use app, but feel free to fork and adapt for your own needs.
