# CloudKit Unique Constraint Fix

## Problem

The app was failing to launch with error:
```
NSCocoaErrorDomain Code=134060
"CloudKit integration does not support unique constraints. 
The following entities are constrained: 
ChannelEntity: channelId, StatusEntity: videoId, VideoEntity: videoId"
```

## Root Cause

When a SwiftData app has CloudKit entitlements (which MeTube has for StatusEntity sync), SwiftData automatically enables CloudKit integration for **all entities in the model**. CloudKit has specific restrictions:

1. **No unique constraints**: CloudKit does not support `@Attribute(.unique)`
2. **All properties must be optional or have default values**: CloudKit requires this for sync flexibility

## Solution Applied

Removed `@Attribute(.unique)` from all three SwiftData entities:

### Files Changed

1. **ChannelEntity.swift** (line 17)
   ```swift
   // Before:
   @Attribute(.unique) var channelId: String = ""
   
   // After:
   var channelId: String = ""
   ```

2. **VideoEntity.swift** (line 18)
   ```swift
   // Before:
   @Attribute(.unique) var videoId: String = ""
   
   // After:
   var videoId: String = ""
   ```

3. **StatusEntity.swift** (line 25)
   ```swift
   // Before:
   @Attribute(.unique) var videoId: String = ""
   
   // After:
   var videoId: String = ""
   ```

## Why This Is Safe

Uniqueness is **already enforced at the application level** in the repository layer:

- **ChannelRepository.saveChannel()** (line 47): Checks for existing channel before inserting
- **VideoRepository.saveVideo()** (line 72): Checks for existing video before inserting
- **StatusRepository.updateStatus()** (line 65): Checks for existing status before inserting

Each repository uses predicates to query for existing entities by ID and either updates the existing entity or inserts a new one. This approach is more flexible than database-level constraints and aligns with offline-first architecture principles.

## CloudKit Requirements Met

All entity properties now satisfy CloudKit requirements:

### ChannelEntity ✅
- `channelId: String = ""` - has default value
- `name: String?` - optional
- `thumbnailURL: String?` - optional
- `channelDescription: String?` - optional
- `uploadsPlaylistId: String?` - optional
- `insertedAt: Date = Date()` - has default value
- `lastModified: Date = Date()` - has default value
- `synced: Bool = false` - has default value

### VideoEntity ✅
- `videoId: String = ""` - has default value
- `channelId: String = ""` - has default value
- `title: String?` - optional
- `videoDescription: String?` - optional
- `thumbnailURL: String?` - optional
- `duration: Double?` - optional
- `publishedAt: Date = Date()` - has default value
- `insertedAt: Date = Date()` - has default value
- `lastModified: Date = Date()` - has default value
- `synced: Bool = false` - has default value

### StatusEntity ✅
- `videoId: String = ""` - has default value
- `status: String = WatchStatus.unknown.rawValue` - has default value
- `lastModified: Date = Date()` - has default value
- `synced: Bool = false` - has default value

## Architecture Preserved

The offline-first architecture remains intact:

- ✅ **Local-first storage**: Videos and channels stored locally in SwiftData
- ✅ **Hub server sync**: HubSyncManager fetches videos from metube.pardeike.net
- ✅ **CloudKit status sync**: StatusSyncManager syncs watch status via CloudKit
- ✅ **Repository pattern**: Clean separation of data access logic
- ✅ **Application-level uniqueness**: Enforced by repository checks
- ✅ **Non-blocking sync**: All network operations run in background

## Testing Instructions

### 1. Clean Build
```bash
cd /path/to/MeTube
xcodebuild -project MeTube.xcodeproj -scheme MeTube clean
```

### 2. Rebuild
```bash
xcodebuild -project MeTube.xcodeproj -scheme MeTube \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### 3. Delete Existing App
- Delete MeTube from your device/simulator
- This ensures a fresh database creation with the new schema

### 4. Install and Launch
- Build and run from Xcode
- The app should now launch without the NSCocoaErrorDomain error

### 5. Verify Functionality
- **Add channels**: Ensure channels can be added without duplicates
- **Sync videos**: Verify HubSyncManager fetches videos correctly
- **Mark status**: Test marking videos as watched/skipped
- **CloudKit sync**: Verify status syncs across devices (if iCloud enabled)
- **Offline mode**: Test app works offline with cached data

## Expected Behavior

### On Fresh Install
1. App launches successfully (no CloudKit error)
2. Empty feed shown with prompt to configure OAuth
3. After OAuth setup, channels can be subscribed
4. Videos sync from hub server to local database
5. Status sync begins in background

### On Subsequent Launches
1. Instant feed display from local database
2. Background sync checks for new videos
3. Status changes sync to CloudKit
4. No blocking operations

## References

- **Apple Documentation**: CloudKit integration requirements
  - fatbobman.com - CloudKit with SwiftData constraints
  - firewhale.io - Unique constraints forbidden with CloudKit
  - alexanderlogan.co.uk - CloudKit SwiftData limitations

- **MeTube Documentation**:
  - `REFACTORING_COMPLETE.md` - Offline-first architecture details
  - `REFACTORING.txt` - Original refactoring guidelines
  - `SERVER_INTEGRATION.md` - Hub server API documentation

## Future Considerations

When adding new SwiftData entities:

1. **Never use `@Attribute(.unique)`** if CloudKit entitlements are present
2. **Ensure all properties are optional or have defaults**
3. **Implement uniqueness checks in repositories** using predicates
4. **Follow the existing entity patterns** in ChannelEntity, VideoEntity, StatusEntity

## Summary

This fix resolves the CloudKit integration error by removing unsupported unique constraints while maintaining application-level uniqueness through the repository pattern. The offline-first architecture, hub server sync, and CloudKit status sync all remain fully functional.
