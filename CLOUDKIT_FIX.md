# CloudKit Unique Constraint Fix & Sync Improvements

## Problems Fixed

### 1. Launch Failure (NSCocoaErrorDomain Code=134060)

The app was failing to launch with error:
```
NSCocoaErrorDomain Code=134060
"CloudKit integration does not support unique constraints. 
The following entities are constrained: 
ChannelEntity: channelId, StatusEntity: videoId, VideoEntity: videoId"
```

### 2. Channel Registration Timeouts

First sync with 216 channels would timeout, leaving user unregistered on hub server and resulting in zero videos.

### 3. User Not Found Errors

After registration timeout, subsequent feed fetches returned `HubError.userNotFound` with no automatic recovery.

### 4. CloudKit Zone Not Found

Status sync failed with "Zone Not Found" because the custom record zone was never created.

### 5. Concurrent Sync Cancellations

Multiple sync tasks running simultaneously caused `NSURLErrorDomain Code=-999` cancellation errors.

## Root Causes

**CloudKit Unique Constraints**: When a SwiftData app has CloudKit entitlements (which MeTube has for StatusEntity sync), SwiftData automatically enables CloudKit integration for **all entities in the model**. CloudKit has specific restrictions:

1. **No unique constraints**: CloudKit does not support `@Attribute(.unique)`
2. **All properties must be optional or have default values**: CloudKit requires this for sync flexibility

**Hub Sync Issues**: Channel registration and feed fetching lacked retry logic and automatic recovery mechanisms.

**CloudKit Zone**: The app attempted to pull changes from a zone that was never created.

**Concurrency**: No guards prevented overlapping sync operations.

## Solutions Applied

### Part 1: CloudKit Unique Constraints (Commits 646184c, 667c35f)

Removed `@Attribute(.unique)` from all three SwiftData entities:

### Files Changed

#### CloudKit Constraint Removal

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

### Part 2: Sync Improvements (Commit ae059f1)

#### HubServerService.swift
- **Channel Registration Retry**: Wrapped `registerChannels()` method with `fetchWithRetry()` helper for automatic retry with exponential backoff on network timeouts

#### HubSyncManager.swift
- **Sync Serialization**: Added `isSyncing` flag to prevent concurrent sync operations
- **Auto Re-registration**: `fetchFeedPage()` now catches `userNotFound` error, fetches channel IDs from local database, re-registers with hub server, and retries feed fetch once
- **Always Register When Needed**: `performSync()` registers channels if server has 0 channels even when local database has channels
- **Page Size Reduction**: Reduced `pageLimit` from 200 to 100 for better first-sync reliability

#### StatusSyncManager.swift
- **Sync Serialization**: Added `isSyncing` flag to prevent concurrent operations
- **Zone Creation**: Added `ensureZoneExists()` method to check for zone existence before pulling changes
- **Auto Zone Creation**: Added `createZone()` method that creates the custom CloudKit record zone if it doesn't exist
- **Enhanced Error Handling**: Improved zone not found error handling in pull operations

## Why This Is Safe

**Uniqueness**: Already enforced at the application level in the repository layer:

- **ChannelRepository.saveChannel()** (line 47): Checks for existing channel before inserting
- **VideoRepository.saveVideo()** (line 72): Checks for existing video before inserting
- **StatusRepository.updateStatus()** (line 65): Checks for existing status before inserting

Each repository uses predicates to query for existing entities by ID and either updates the existing entity or inserts a new one.

**Retry Logic**: Uses exponential backoff (1s, 2s, 4s) with max 3 attempts. Preserves all existing logging.

**Sync Serialization**: Single boolean flag check at entry point prevents race conditions without complex locking.

**Zone Creation**: Only creates zone once, subsequent syncs skip creation check. Idempotent operation.

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

#### Basic Operations
- **Launch**: App starts without NSCocoaErrorDomain error
- **OAuth**: User can sign in and tokens persist across launches
- **Add channels**: Channels can be added without duplicates

#### Hub Sync (First Run with 216 channels)
- **Registration**: Channel registration completes without timeout (uses retry logic)
- **Feed Fetch**: Videos appear in feed after registration
- **Auto Recovery**: If registration times out, app auto re-registers on next feed fetch
- **No Duplicates**: Videos are deduplicated even with multiple sync attempts

#### CloudKit Status Sync
- **Zone Creation**: CloudKit zone created automatically on first sync
- **Status Sync**: Watch/skip status syncs to CloudKit
- **Cross-Device**: Status appears on other devices (if iCloud enabled)
- **No Zone Errors**: No "Zone Not Found" errors in logs

#### Concurrency
- **No Cancellations**: No `NSURLErrorDomain Code=-999` errors
- **Single Sync**: Multiple sync requests don't cause conflicts
- **Logs Show Skipping**: Logs show "Sync already in progress, skipping" when appropriate

## Expected Behavior

### On Fresh Install
1. App launches successfully (no CloudKit error)
2. Empty feed shown with prompt to configure OAuth
3. After OAuth setup, 216 channels register with retry logic (3 attempts with backoff)
4. Videos sync from hub server to local database (100 videos per page)
5. CloudKit zone created automatically
6. Status sync begins in background
7. Tokens persist to keychain and CloudKit

### On Subsequent Launches
1. OAuth tokens load from keychain (no re-login required)
2. Instant feed display from local database
3. Background sync checks for new videos (if > 1 hour since last sync)
4. Status changes sync to CloudKit (if > 5 minutes since last sync)
5. No concurrent sync operations (serialized by isSyncing flag)
6. No blocking operations

### After Timeout/Error Recovery
1. If channel registration times out, user not found error occurs on feed fetch
2. App automatically fetches channel IDs from local database
3. Re-registration attempted automatically
4. Feed fetch retried after successful re-registration
5. User gets videos without manual intervention

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
