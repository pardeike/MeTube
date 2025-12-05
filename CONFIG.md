# MeTube Configuration Guide

This guide walks you through setting up all the necessary backend services and configuration for the MeTube iOS app. Follow each section carefully in order.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Google Cloud Console Setup](#google-cloud-console-setup)
3. [YouTube Data API Configuration](#youtube-data-api-configuration)
4. [OAuth 2.0 Credentials](#oauth-20-credentials)
5. [Apple Developer Account Setup](#apple-developer-account-setup)
6. [Xcode Project Configuration](#xcode-project-configuration)
7. [CloudKit Setup](#cloudkit-setup)
8. [Running the App](#running-the-app)
9. [Troubleshooting](#troubleshooting)
10. [Content Fetching & Refresh Behavior](#content-fetching--refresh-behavior)
11. [API Quota Management](#api-quota-management)
12. [Background Refresh Configuration](#background-refresh-configuration)

---

## Prerequisites

Before you begin, ensure you have:

- **Mac** with macOS Sonoma 14.0 or later
- **Xcode 15.0** or later (download from [Mac App Store](https://apps.apple.com/app/xcode/id497799835))
- **Apple ID** (free tier works for development on simulators, paid Apple Developer account required for device testing)
- **Google Account** with an active YouTube Premium subscription
- **iPhone** running iOS 17.0+ (or use the iOS Simulator)

---

## Google Cloud Console Setup

### Step 1: Create a Google Cloud Project

1. Open your browser and go to [Google Cloud Console](https://console.cloud.google.com/)

2. Sign in with your Google account (the same one you use for YouTube)

3. At the top of the page, click the project dropdown (it may say "Select a project" or show your current project name)

4. In the popup window, click **New Project** in the top right

5. Fill in the project details:
   - **Project name**: `MeTube` (or any name you prefer)
   - **Organization**: Leave as "No organization" if you're using a personal account
   - **Location**: Leave as default

6. Click **Create** and wait for the project to be created (this takes a few seconds)

7. Once created, make sure your new project is selected in the project dropdown at the top

### Step 2: Enable Billing (Required for API Access)

> **Note**: YouTube Data API has a generous free quota (10,000 units/day). You won't be charged for normal usage, but billing must be enabled.

1. In the Google Cloud Console, click the hamburger menu (☰) in the top left

2. Navigate to **Billing**

3. Click **Link a billing account** or **Manage billing accounts**

4. If you don't have a billing account:
   - Click **Create Account**
   - Follow the prompts to set up a billing account
   - You can use a credit card; you won't be charged for API usage within free tier limits

5. Link your billing account to the MeTube project

---

## YouTube Data API Configuration

### Step 1: Enable the YouTube Data API v3

1. In Google Cloud Console, ensure your MeTube project is selected

2. Click the hamburger menu (☰) and navigate to **APIs & Services** > **Library**

3. In the search bar, type `YouTube Data API v3`

4. Click on **YouTube Data API v3** in the results

5. Click the blue **Enable** button

6. Wait for the API to be enabled (you'll be redirected to the API dashboard)

### Step 2: Verify API is Enabled

1. Go to **APIs & Services** > **Enabled APIs & services**

2. Confirm you see **YouTube Data API v3** in the list

3. Click on it to view usage metrics and quotas

### Step 3: Understanding API Quotas

The YouTube Data API has a default quota of **10,000 units per day**. MeTube uses these operations:

| Operation | Cost | MeTube Usage |
|-----------|------|--------------|
| subscriptions.list | 1 unit | Fetching your subscribed channels |
| playlistItems.list | 1 unit | Fetching videos from each channel |
| videos.list | 1 unit | Getting video durations (to filter Shorts) |

**Typical daily usage**: 50-200 units depending on number of subscriptions

If you need more quota, you can request an increase in the Cloud Console under **APIs & Services** > **YouTube Data API v3** > **Quotas**.

---

## OAuth 2.0 Credentials

### Step 1: Configure the OAuth Consent Screen

Before creating credentials, you must configure the OAuth consent screen.

1. In Google Cloud Console, go to **APIs & Services** > **OAuth consent screen**

2. Select **External** as the User Type (unless you have a Google Workspace account and want internal-only)

3. Click **Create**

4. Fill in the **App information**:
   - **App name**: `MeTube`
   - **User support email**: Select your email from the dropdown
   - **App logo**: Optional, skip for now

5. In the **App domain** section:
   - Leave all fields blank (not required for personal use)

6. In **Developer contact information**:
   - Enter your email address

7. Click **Save and Continue**

### Step 2: Configure Scopes

1. On the Scopes page, click **Add or Remove Scopes**

2. In the filter box, search for `youtube.readonly`

3. Check the box next to **`.../auth/youtube.readonly`** (View your YouTube account)
   - This scope allows the app to read your subscriptions and video data
   - It does NOT allow posting, commenting, or modifying your YouTube account

4. Click **Update**

5. Click **Save and Continue**

### Step 3: Add Test Users

Since your app is in "Testing" mode, you need to add yourself as a test user.

1. On the Test users page, click **Add Users**

2. Enter your Google email address (the one you use for YouTube)

3. Click **Add**

4. Click **Save and Continue**

5. Review the summary and click **Back to Dashboard**

> **Note**: Your app will stay in "Testing" mode, which is fine for personal use. Only test users you've added can authenticate.

### Step 4: Create OAuth 2.0 Client ID

1. Go to **APIs & Services** > **Credentials**

2. Click **+ Create Credentials** at the top

3. Select **OAuth client ID**

4. For **Application type**, select **iOS**

5. Fill in the details:
   - **Name**: `MeTube iOS Client`
   - **Bundle ID**: `com.metube.app`
     > **Important**: This must match exactly what's in the Xcode project. If you change the bundle ID in Xcode, update it here too.

6. Click **Create**

7. A popup will appear with your **Client ID**. It looks like:
   ```
   123456789012-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com
   ```

8. **Copy the Client ID** and save it somewhere safe. You'll need it when configuring the app.

9. Click **OK** to close the popup

### Step 5: Download Credentials (Optional)

1. In the Credentials list, find your new OAuth client

2. Click the download icon (⬇️) to download the credentials JSON file

3. Keep this file safe; it contains your client configuration

---

## Apple Developer Account Setup

### For Simulator Testing (Free)

If you only want to test on the iOS Simulator, you can use a free Apple ID:

1. Open Xcode
2. Go to **Xcode** > **Settings** (or **Preferences** on older versions)
3. Click the **Accounts** tab
4. Click **+** and select **Apple ID**
5. Sign in with your Apple ID

> **Note**: CloudKit features require a paid developer account for device testing.

### For Device Testing (Paid - $99/year)

To run the app on a physical iPhone with CloudKit sync:

1. Go to [Apple Developer Program](https://developer.apple.com/programs/)

2. Click **Enroll**

3. Sign in with your Apple ID

4. Complete the enrollment process ($99 USD/year)

5. Once enrolled, add your account to Xcode:
   - Open Xcode > **Settings** > **Accounts**
   - Click **+** > **Apple ID**
   - Sign in with your enrolled Apple ID

---

## Xcode Project Configuration

### Step 1: Open the Project

1. Clone or download the MeTube repository

2. Open `MeTube.xcodeproj` in Xcode

3. Wait for Xcode to index the project and resolve packages

### Step 2: Configure Signing

1. In the Project Navigator (left sidebar), click on **MeTube** (the blue project icon at the top)

2. Select the **MeTube** target in the targets list

3. Click the **Signing & Capabilities** tab

4. Under **Signing**:
   - Check **Automatically manage signing**
   - Select your **Team** from the dropdown (your Apple ID or Developer account)
   - The **Bundle Identifier** should be `com.metube.app`
   
   > If you get signing errors, try changing the Bundle Identifier to something unique like `com.yourname.metube`

### Step 3: Verify Capabilities

In the **Signing & Capabilities** tab, verify these capabilities are present:

1. **iCloud**
   - Check **CloudKit** is enabled
   - Under Containers, you should see `iCloud.com.metube.app`
   - If not, click **+** and add it

2. If **iCloud** capability is missing:
   - Click **+ Capability**
   - Search for and add **iCloud**
   - Check **CloudKit**
   - Add the container `iCloud.com.metube.app`

### Step 4: Update Bundle Identifier (If Needed)

If you changed the Bundle Identifier for signing:

1. Go to the **General** tab

2. Update the **Bundle Identifier**

3. Update these files to match:

   **Info.plist** - Update the URL scheme:
   ```xml
   <key>CFBundleURLSchemes</key>
   <array>
       <string>your.new.bundle.id</string>
   </array>
   ```

   **MeTube.entitlements** - Update the CloudKit container:
   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array>
       <string>iCloud.your.new.bundle.id</string>
   </array>
   ```

4. Update the Google Cloud Console OAuth Client ID with the new Bundle ID

---

## CloudKit Setup

CloudKit stores your video watch status and syncs it across devices.

### Step 1: Access CloudKit Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/)

2. Sign in with your Apple Developer account

3. Select your app's container (`iCloud.com.metube.app`)

### Step 2: Create Record Types (Automatic)

The app automatically creates the necessary record types when you first save data. However, you can manually create them:

1. In CloudKit Dashboard, click **Schema**

2. Click **Record Types**

3. Create a record type called **Video** with these fields:
   - `title` (String)
   - `channelId` (String)
   - `channelName` (String)
   - `publishedDate` (Date/Time)
   - `duration` (Double)
   - `thumbnailURL` (String)
   - `description` (String)
   - `status` (String)

4. Create a record type called **Channel** with these fields:
   - `name` (String)
   - `thumbnailURL` (String)
   - `description` (String)
   - `uploadsPlaylistId` (String)

### Step 3: Deploy Schema to Production (Optional)

If you want to use CloudKit in production:

1. In CloudKit Dashboard, go to **Schema**

2. Click **Deploy Schema to Production**

3. Review and confirm

> **Note**: For personal use in development mode, this step is not required.

---

## Running the App

### First Run Setup

1. **Build and Run** the app (⌘R) on your device or simulator

2. On the login screen, tap **Configure OAuth** at the bottom

3. Enter your **Google Client ID** (the one you copied earlier):
   ```
   123456789012-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com
   ```

4. Tap **Save Configuration**

5. Tap **Sign in with Google**

6. A web view will appear asking you to sign in to your Google account

7. Review the permissions and click **Allow**

8. The app will fetch your subscriptions and display your feed

### Subsequent Launches

After the initial setup, the app will:
- Remember your Client ID
- Automatically refresh your authentication token
- Sync video status via CloudKit

---

## Troubleshooting

### "Google Client ID not configured"

**Solution**: Tap "Configure OAuth" on the login screen and enter your Client ID.

### "Error 400: redirect_uri_mismatch"

**Cause**: The Bundle ID in your OAuth client doesn't match the app.

**Solution**: 
1. Go to Google Cloud Console > **Credentials**
2. Edit your OAuth client
3. Verify the Bundle ID matches your Xcode project exactly

### "Access blocked: This app's request is invalid"

**Cause**: OAuth consent screen is not configured or you're not a test user.

**Solution**:
1. Go to **OAuth consent screen** in Google Cloud Console
2. Make sure your email is added as a test user
3. Verify the `youtube.readonly` scope is enabled

### "The operation couldn't be completed. (com.apple.AuthenticationServices.WebAuthenticationSession error 1.)"

**Cause**: User cancelled the authentication flow.

**Solution**: Try signing in again and complete the entire flow.

### CloudKit errors

**Cause**: iCloud is not signed in or container is misconfigured.

**Solution**:
1. On your device, go to **Settings** > **Apple ID** > **iCloud**
2. Make sure iCloud is enabled
3. In Xcode, verify the CloudKit container matches your entitlements

### "Quota exceeded for quota metric"

**Cause**: You've exceeded the YouTube API daily quota.

**Solution**: Wait until the quota resets (midnight Pacific Time) or request a quota increase in Google Cloud Console.

### Videos not loading

**Cause**: API calls may be failing silently.

**Solution**:
1. Check the Xcode console for error messages
2. Verify your OAuth token is valid by signing out and back in
3. Make sure YouTube Data API is enabled in Cloud Console

### App crashes on launch

**Solution**:
1. Clean build folder: **Product** > **Clean Build Folder** (⇧⌘K)
2. Delete derived data: Go to **Xcode** > **Settings** > **Locations** > click arrow next to Derived Data path > delete the MeTube folder
3. Rebuild the project

---

## Security Notes

- Your OAuth Client ID is stored locally in UserDefaults (not sensitive, as iOS apps are sandboxed)
- OAuth tokens are stored in the iOS Keychain (encrypted)
- All CloudKit data is stored in your private iCloud container
- The app only requests read-only access to YouTube (`youtube.readonly` scope)
- No data is sent to any third-party servers

---

## Quick Reference

| Setting | Value |
|---------|-------|
| Bundle ID | `com.metube.app` |
| OAuth Redirect URI | `com.metube.app://oauth2callback` |
| CloudKit Container | `iCloud.com.metube.app` |
| Required API | YouTube Data API v3 |
| OAuth Scope | `https://www.googleapis.com/auth/youtube.readonly` |
| iOS Target | 17.0+ |
| Background Task ID | `com.metube.app.refresh` |
| Daily Quota Limit | 10,000 units |

---

## Content Fetching & Refresh Behavior

MeTube uses a sophisticated fetching system designed to handle hundreds of subscriptions efficiently while never missing new content.

### Refresh Types

#### Full Refresh
- Triggered on first launch or when you request it via the menu
- Fetches all subscriptions (paginated, 50 at a time)
- Gets uploads playlist ID for each channel
- Fetches up to 20 recent videos per channel
- Automatically filters out YouTube Shorts (< 60 seconds)
- Performed automatically once every 24 hours

#### Incremental Refresh
- Default refresh when pulling down or re-opening the app
- Only fetches 5 recent videos per channel (much faster)
- Merges new videos with existing ones (no duplicates)
- Much more quota-efficient

#### Background Refresh
- Runs periodically when app is in background (every 15 minutes if system allows)
- Fetches only 3 recent videos per channel to minimize quota usage
- Updates new video count badge
- iOS controls actual execution timing based on battery, network, and usage patterns

### Visual Loading Indicators

The app shows detailed progress during loading:

1. **"Fetching Subscriptions..."** - Getting your channel list
2. **"Loading Videos (X/Y): Channel Name"** - Progress through channels with a progress bar
3. **"Syncing Status..."** - Loading your watch history from iCloud
4. **"Checking for Updates..."** - During incremental refresh

When refreshing with existing data, a subtle overlay shows the current operation without blocking the interface.

### Ensuring No Missed Content

The app uses several strategies to ensure you don't miss new videos:

1. **Incremental merging**: New videos are merged with existing ones, never replacing
2. **Full refresh daily**: Automatically performs a complete refresh every 24 hours
3. **Background updates**: Checks for new content even when the app isn't open
4. **New video counter**: Shows how many new videos were found since last check

---

## API Quota Management

### Understanding YouTube API Quota

YouTube Data API has a daily quota of **10,000 units** (resets at midnight Pacific Time).

#### Quota Costs

| Operation | Cost | MeTube Usage |
|-----------|------|--------------|
| subscriptions.list | 1 unit per request | ~1-5 units (paginated for many subscriptions) |
| channels.list | 1 unit per request | ~1-5 units (batched by 50) |
| playlistItems.list | 1 unit per request | 1 unit per channel |
| videos.list | 1 unit per request | ~1-3 units per channel (batched by 50) |

#### Typical Usage Examples

| Scenario | Subscriptions | Full Refresh | Incremental | Daily Usage |
|----------|---------------|--------------|-------------|-------------|
| Light user | 50 channels | ~150 units | ~75 units | ~300 units |
| Medium user | 150 channels | ~450 units | ~225 units | ~900 units |
| Heavy user | 500 channels | ~1,500 units | ~750 units | ~3,000 units |

### Quota Tracking in App

The app tracks your quota usage:

1. Tap the **menu** (filter icon) in the Feed view
2. Select **"API Quota"** to see:
   - Units used today
   - Remaining quota
   - Progress bar visualization
   - When quota resets

### Quota Warning Levels

- **Normal** (< 80%): Green/Blue indicator
- **Warning** (80-99%): Orange indicator - consider waiting until tomorrow
- **Exceeded** (100%): Red indicator - must wait for reset

### What Happens When Quota is Exceeded

1. The app stops making API calls
2. Your existing videos remain viewable
3. Watch status still syncs via CloudKit
4. Full functionality resumes after midnight PT

### Tips for Managing Quota

1. **Use incremental refresh** - Pull to refresh uses less quota than full refresh
2. **Avoid excessive refreshing** - Videos update at most every few minutes
3. **Background refresh is efficient** - Uses minimal quota automatically
4. **Request quota increase** - If you have many subscriptions, request more quota from Google Cloud Console

### Requesting a Quota Increase

If you have hundreds of subscriptions and need more quota:

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Navigate to **APIs & Services** > **YouTube Data API v3**
3. Click **Quotas**
4. Click **Edit Quotas** (pencil icon)
5. Fill in the request form explaining personal use
6. Submit and wait for approval (usually 24-48 hours)

---

## Background Refresh Configuration

The app supports iOS background refresh to keep content updated.

### How It Works

1. When you close the app, it schedules a background refresh task
2. iOS decides when to actually run the task based on:
   - Device battery level
   - Network conditions
   - Your usage patterns
   - System resources
3. The app fetches minimal data (3 videos per channel)
4. New video count is updated for when you return

### Enabling Background Refresh

1. Go to **Settings** > **General** > **Background App Refresh**
2. Make sure **Background App Refresh** is ON
3. Scroll to find **MeTube** and ensure it's enabled

### Limitations

- iOS controls when background tasks run (not guaranteed every 15 minutes)
- Background refresh uses minimal quota to avoid exhausting your daily limit
- On low battery, iOS may skip background refreshes

---

## Need Help?

If you encounter issues not covered in this guide:

1. Check the Xcode console for detailed error messages
2. Verify all IDs and configurations match exactly
3. Ensure your Google account has YouTube Premium (required for ad-free playback)
4. Try signing out and back in to refresh your authentication

Last updated: December 2024
