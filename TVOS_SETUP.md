# MeTube tvOS Setup Guide

This guide explains how to add and configure the tvOS target for MeTube.

## Overview

MeTube supports both iOS and tvOS platforms. The tvOS version shares the same core functionality:
- SwiftData for local data persistence
- CloudKit for syncing watch status and settings across devices
- YouTube feed from the hub server
- Direct video playback using AVPlayer with highest quality streams

**Important**: The tvOS version relies on iCloud to sync authentication credentials from the iOS app. Users must first sign in on their iPhone or iPad, and the credentials will automatically sync to Apple TV via iCloud Keychain.

## Setting Up tvOS Target in Xcode

### Step 1: Add New Target

1. Open `MeTube.xcodeproj` in Xcode
2. Click on the project in the navigator (the blue project icon)
3. At the bottom of the targets list, click the **+** button
4. Select **tvOS** > **App**
5. Configure the new target:
   - **Product Name**: `MeTube-tvOS`
   - **Bundle Identifier**: `com.metube.app.tvos`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - Click **Finish**

### Step 2: Share Source Files

Add the following existing source files to the tvOS target:

#### Models (All shared)
- `MeTube/Models/Channel.swift`
- `MeTube/Models/Video.swift`
- `MeTube/Models/YouTubeAPIModels.swift`
- `MeTube/Models/PlayerConfig.swift`
- `MeTube/Models/AppSettings.swift`
- `MeTube/Models/ModelConverters.swift`
- `MeTube/Models/Persistence/ChannelEntity.swift`
- `MeTube/Models/Persistence/VideoEntity.swift`
- `MeTube/Models/Persistence/StatusEntity.swift`

#### Services (All shared)
- `MeTube/Services/AuthenticationManager.swift`
- `MeTube/Services/CloudKitService.swift`
- `MeTube/Services/YouTubeService.swift`
- `MeTube/Services/YouTubeStreamExtractor.swift`
- `MeTube/Services/HubServerService.swift`
- `MeTube/Services/Logger.swift`
- `MeTube/Services/Sync/HubSyncManager.swift`
- `MeTube/Services/Sync/StatusSyncManager.swift`

#### Repositories (All shared)
- `MeTube/Repositories/ChannelRepository.swift`
- `MeTube/Repositories/VideoRepository.swift`
- `MeTube/Repositories/StatusRepository.swift`

#### ViewModels (All shared)
- `MeTube/ViewModels/FeedViewModel.swift`
- `MeTube/ViewModels/PlayerViewModel.swift`

#### Shared Utilities
- `MeTube/Shared/PlatformUtilities.swift`

#### App Entry Points (Shared)
- `MeTube/App/MeTubeApp.swift`
- `MeTube/App/ContentView.swift`

#### tvOS-Specific Views
- `MeTube/Views/tvOS/TVLoginView.swift`
- `MeTube/Views/tvOS/TVFeedView.swift`
- `MeTube/Views/tvOS/TVChannelsView.swift`
- `MeTube/Views/tvOS/TVVideoPlayerView.swift`
- `MeTube/Views/tvOS/TVVideoRowView.swift`

#### Resources
- `MeTube/Resources/Assets.xcassets` (add tvOS-specific app icons)

### Step 3: Configure Entitlements

1. Copy `MeTube-tvOS/MeTube-tvOS.entitlements` to your project
2. In Xcode, select the MeTube-tvOS target
3. Go to **Signing & Capabilities**
4. Add these capabilities:
   - **iCloud** (enable CloudKit with container `iCloud.com.metube.app`)
   - **Keychain Sharing** (add access group `$(AppIdentifierPrefix)com.metube.app.shared`)

### Step 4: Configure Build Settings

1. Select the MeTube-tvOS target
2. Go to **Build Settings**
3. Set:
   - **tvOS Deployment Target**: 17.0 (or later)
   - **Info.plist File**: `MeTube-tvOS/Info.plist`

### Step 5: Add App Icons

1. In `Assets.xcassets`, add a new **App Icon (tvOS)** asset
2. Provide the required icon sizes:
   - App Icon - App Store: 1280x768 px (large)
   - App Icon - Home Screen: Multiple sizes (400x240, 800x480)

### Step 6: Update iOS Entitlements

For iCloud Keychain sync to work between iOS and tvOS, update the iOS entitlements:

1. Open `MeTube/MeTube.entitlements`
2. Add the keychain-access-groups key with the shared group

## How Authentication Works

### iOS (Primary Sign-In)
1. User opens MeTube on iPhone/iPad
2. Taps "Sign in with Google"
3. ASWebAuthenticationSession handles OAuth flow
4. Tokens stored in iCloud Keychain (synchronized)
5. Settings saved to CloudKit

### tvOS (Synced Credentials)
1. User opens MeTube on Apple TV
2. App shows "Sign in with your iPhone or iPad" screen
3. App checks iCloud Keychain for tokens
4. If found, automatically authenticates
5. User can tap "Check for Login" to refresh

## Video Quality

The app automatically selects the **highest quality** video stream available:
- Prefers direct streams (MP4/WebM) over HLS for maximum quality
- Supports up to 4K/2160p when available
- Falls back to HLS adaptive streaming if direct streams unavailable

## Troubleshooting

### "Sign in with your iPhone or iPad" stays visible
- Ensure both devices are signed into the same iCloud account
- Check that iCloud Keychain is enabled on both devices
- Wait a few minutes for sync, then tap "Check for Login"

### Video won't play
- Check internet connection
- Try force-closing and reopening the app
- The stream extraction may fail if YouTube changes their API

### Missing data on tvOS
- Ensure CloudKit sync is enabled
- Check that the iOS app has synced recently
- Data syncs via CloudKit (video status) and the hub server (feed)

## Architecture Notes

### Platform Conditionals
The codebase uses `#if os(tvOS)` and `#if os(iOS)` to provide platform-specific implementations:
- UI components adapted for focus-based navigation on tvOS
- Authentication flow differs (web auth on iOS, iCloud sync on tvOS)
- Background refresh only on iOS

### Shared Code
Most business logic is shared between platforms:
- Data models
- Network services
- Local persistence (SwiftData)
- Cloud sync (CloudKit)
- Video stream extraction

### tvOS-Specific Adaptations
- `TVLoginView`: Guides users to sign in via iOS
- `TVFeedView`: Grid layout with focus navigation
- `TVVideoPlayerView`: Uses native AVPlayerViewController
- `TVChannelsView`: Card-based channel grid
- `TVVideoRowView`: Larger thumbnails for TV viewing
