# MeTube

YouTube Subscription Feed App: Architectural Plan

Introduction and Purpose

This iOS/tvOS app is designed as a distraction-free YouTube client focused solely on subscribed channel content. The goal is to eliminate YouTube’s algorithmic recommendations, Shorts feeds, and other distractions by providing only the videos from channels you subscribe to. Using your YouTube Premium account and Google Developer credentials, the app will aggregate new uploads from your subscriptions (excluding Shorts) in chronological order. It will track which videos you’ve watched or skipped, allow filtering and channel browsing, and support playback on Apple TV via AirPlay. This document outlines a comprehensive architecture and battle plan for building the app in SwiftUI, detailing data flow, components, and integration points. All design choices prioritize simplicity, native functionality, and your personal use-case (no App Store distribution needed).

Key Features and Requirements
	•	Chronological Subscription Feed: Fetch all new videos from your subscribed channels and display them in a time-sorted list (e.g. newest first or grouped by date). No non-subscribed or recommended content is shown ￼. Shorts (short-form vertical videos) are excluded from the feed.
	•	Watch Status Tracking: Maintain a state (unwatched, watched, or skipped) for each video. Unwatched (unseen) videos appear in the main feed. You can mark a video as watched (automatically when played to completion or manually) or mark it as skipped to remove it from the unseen feed without watching.
	•	Filtering and Search: Enable filtering of the video list by channel or keywords. For example, a search bar could let you quickly filter the feed for a channel name or video title. This helps find specific content or focus on one channel’s videos.
	•	Channel Browsing: Provide a view of all subscribed channels (perhaps a “Channels” tab or screen) showing each channel (with an optional count of unseen videos per channel). Tapping a channel opens that channel’s page with its recent videos. This allows quick jumping to any channel to browse or find older videos (even those already watched) to show others.
	•	Video Playback (Native with AirPlay): Allow playback of videos within the app with an option to stream to Apple TV. The player should support AirPlay so you can easily hand off the video to an Apple TV on the same network. Using the native iOS player controls or YouTube’s official player should permit AirPlay streaming. Full-screen playback on the device and basic controls (play/pause, seek, etc.) are required.
	•	Sync Across Devices: Use Apple’s CloudKit to store subscription data (if needed) and, importantly, the watch/skipped status of videos in your private iCloud database. This ensures the app state (what you’ve watched or skipped) stays consistent between your iPhone and a potential future tvOS app (or another iOS device) ￼. No separate login is required for iCloud beyond the default Apple ID on the device (since this is a personal app).
	•	No Distractions: Omit YouTube’s suggestions, comments, likes, or any algorithmic content. The app’s interface should be clean and minimal – just a list of videos and a way to play them. This is to keep focus on “quality content” from your chosen channels.

Technology Stack and Components
	•	Platform: Native iOS (targeting your iPhone 16 Pro Max) built with SwiftUI. SwiftUI will be used for all interface components to ensure a modern, native look and compatibility with iOS 16/17+. A companion tvOS app can be built with the same logic (SwiftUI for tvOS) or you can use AirPlay from the iOS app to play videos on Apple TV.
	•	Language: Swift (with SwiftUI and Combine or async/await for asynchronous tasks). No Objective-C or web wrappers except where using provided SDKs.
	•	Data Source: Official YouTube Data API v3 for retrieving data about subscriptions and videos. The app will use authorized requests to the YouTube API (leveraging your Google Developer account and OAuth credentials) to fetch:
	•	The list of channels you are subscribed to (requires OAuth with the mine=true parameter) ￼.
	•	Recent uploads from each subscribed channel (via channels’ “uploads” playlist or search API, detailed below).
	•	Video Playback: Use YouTube’s official iOS Player helper library or native AVPlayer:
	•	Preferred approach: YouTube iOS Player SDK (which uses an embedded web iframe player) for simplicity. This involves adding a YTPlayerView in SwiftUI (via UIViewRepresentable) and loading videos by ID ￼. The Google player SDK handles streaming and provides on-screen controls (including fullscreen toggle) ￼. This is straightforward and aligned with YouTube’s terms, ensuring ad-free playback for Premium accounts.
	•	Alternative approach: Use AVPlayer with a direct video stream URL (retrieved via YouTube Data API or a third-party parser). This would give more native control (system player UI, Picture-in-Picture, etc.) but is more complex and potentially against YouTube’s ToS if not using official APIs. For the first version, using the official player is simpler.
	•	Cloud Storage: CloudKit (private database) for app data persistence. This will store the watch/skipped status of videos (and possibly cached video metadata or channel info). CloudKit enables syncing these states across your devices seamlessly ￼ ￼. No separate backend server is required.
	•	Local Storage & Caching: The app can cache fetched data on-device (using a lightweight database or structures in memory). Since CloudKit and the YouTube API are the sources of truth, a full Core Data store might be optional. However, using an on-device database (or the new SwiftData/Core Data with CloudKit sync) is beneficial for offline access or simply to avoid re-fetching data every time. We can define data models and use CloudKit as the backing store.
	•	Authentication: Google OAuth 2.0 for YouTube access and Apple iCloud for CloudKit:
	•	The app will incorporate a Google sign-in flow (for your account) to obtain an OAuth token with permission to read your YouTube subscriptions and videos (YouTube Data API scope like youtube.readonly). This is a one-time sign-in since it’s your personal app. Tokens (and refresh tokens) will be stored securely (e.g., in Keychain) for renewing API access.
	•	For CloudKit, as long as you are logged into an Apple ID on the device with iCloud enabled, no explicit login is needed. The app’s iCloud container (identified in the Apple Developer portal) will be used to save data. We will ensure iCloud capability is enabled and handle the case where iCloud is unavailable by warning the user (you) to log in ￼.

Data Flow and YouTube Integration

1. Retrieving Subscriptions: On first launch (or periodically), the app will fetch your subscription list via the YouTube Data API. This requires an authorized GET request to youtube/v3/subscriptions?part=snippet&mine=true ￼. The API will return the channels you subscribe to (channel IDs and names, plus possibly thumbnails) in batches of up to 50 channels per request. All channel IDs will be stored in memory or a local cache (and possibly in CloudKit for persistence, though we can always re-fetch from API if needed).

2. Fetching Videos from Subscribed Channels: YouTube’s API does not provide a single “subscription feed” endpoint for recent uploads across all channels ￼, so the app must gather videos channel-by-channel:
	•	For each subscribed channel ID, retrieve that channel’s uploads. YouTube channels have an “Uploads” playlist (accessible via the Channels API or directly via a known playlist ID). One approach:
	•	Use channels.list with part=contentDetails to get the channel’s uploads playlist ID (in contentDetails.relatedPlaylists.uploads). Then use playlistItems.list on that playlist with part=snippet,contentDetails to get recent videos. This can retrieve video IDs, titles, thumbnails, publish dates, etc.
	•	Alternatively, use the Search API with the channelId filter: e.g., search.list?channelId=XYZ&type=video&order=date&publishedAfter=... to get recent videos for that channel. However, this costs more quota (100 units per query) and may be unnecessary if using playlistItems.
	•	New Videos Only: To keep it efficient, the app can track the last video fetched per channel (e.g., latest publish date or video ID seen) and only request videos published after that on subsequent refreshes. On first run, it might fetch a fixed number (e.g., last 10 or 20 videos per channel) to populate history.
	•	Exclude Shorts: We will filter out YouTube Shorts from the results. Shorts are typically videos under 60 seconds and often have a blank description or are marked with a special category. Since the Data API doesn’t explicitly label “Shorts”, we will apply a rule to exclude videos whose duration is very short. For example, after retrieving video IDs from playlistItems, we can call videos.list?part=contentDetails&id=... to get the duration of each video and ignore those with duration < 60s (or use Search API filters). The YouTube API’s search can also filter by duration; e.g., using videoDuration=medium or long excludes short videos ￼. This ensures the feed only shows longer, standard YouTube videos (the “quality content” you want).
	•	Data to Store per Video: For each video fetched, the app will capture key metadata:
	•	Video ID (YouTube identifier).
	•	Title.
	•	Channel name (or ID reference to channel).
	•	Publish date/time (for sorting chronologically).
	•	Thumbnail URL (for display in the list).
	•	Duration (to possibly display or use for filtering).
	•	Status – initially, new videos are marked as unwatched by default.
	•	The app will merge all fetched videos into a unified list (the subscription feed) sorted by publish time. This unified feed generation happens either on the device after fetching or by querying all channels and then sorting.

3. Updating Feed and Refresh Strategy: The app can refresh this feed on demand (e.g., pull-to-refresh) or periodically (since it’s for personal use, manual refresh is fine). When refreshing:
	•	It re-fetches any new videos from each channel (published since last check).
	•	Adds them to the local list as unwatched.
	•	Older videos (already watched/skipped) remain recorded in CloudKit so they won’t reappear as new. If needed, the app can keep an internal list of all video IDs seen before to avoid duplication.
	•	Quota considerations: fetching subscriptions (cost 1 unit) and playlistItems (cost 1 per 5 videos) are lightweight ￼. Even if you have e.g. 100 channels, fetching 100 playlists of 5 items each ~ 100 units, well within daily 10,000 quota.

4. Alternative Data Fetch (Optional): As an alternative to using the Data API for every channel, the app could use YouTube’s RSS feeds. Each channel has an RSS feed of uploads at https://www.youtube.com/feeds/videos.xml?channel_id=CHANNEL_ID. This requires only the channel ID and no quota/auth once you have the list of channels ￼. However, the RSS feed returns only the latest ~15 videos and has no pagination ￼. If you check frequently, this may be sufficient. For completeness, our app will use the official API for robust control, but it’s worth noting RSS as a lightweight method (no API key usage) for future consideration.

Data Model and Storage Design

We will define simple Swift models to represent channels and videos, plus use CloudKit to persist the watch status:
	•	Channel Model: Represents a YouTube channel subscription.
	•	Properties: id (YouTube channel ID), name (channel title), and possibly thumbnailURL (channel avatar) for a nicer UI.
	•	This data comes from the subscriptions API response (snippet part).
	•	We might not need to store channels persistently (we can fetch from API), but caching them (in CloudKit or locally) can speed up UI and allow showing channel list offline.
	•	Video Model: Represents a YouTube video (primarily from your subs).
	•	Properties: id (video ID), title, channelId (or a link to Channel model), publishedDate, duration, thumbnailURL, status (an enum or flag for unwatched/watched/skipped).
	•	The status is the main piece of state we track in CloudKit. Initially every video is unwatched. When you play a video or mark it, it becomes watched. If you decide to skip a video (not interested), it becomes skipped. Watched or skipped videos are considered “seen” and will be excluded from the default feed view.
	•	We will create a CloudKit record type, e.g. VideoStatus, with fields: videoID (string, primary key), status (string or int), maybe lastWatchedDate. Alternatively, we can store a record per video that includes status and perhaps also the title/channel for reference. The schema might have record type “Video” with fields: id (video ID) as record name, title, channelId, published, status. This way we can fetch and update status easily by record ID. Only status truly needs syncing, but storing title etc. in the record can help if we want to display some info even if not calling the API.
	•	CloudKit Usage: We’ll use the private CloudKit database tied to your iCloud account ￼. This means all data is only accessible to you, and it syncs across your devices automatically. By using CloudKit, if you later install the app on another device (or if we create a tvOS version), the same subscription video statuses will be available (so you don’t re-see videos you already dealt with). CloudKit is also reliable for storing a moderate number of records (your subscriptions and their videos). Each video you track can correspond to one record; CloudKit can easily handle hundreds or thousands of records for a single user.
	•	Data Flow for Status Updates: When you mark a video as watched or skipped, the app will update the CloudKit record (or create it if first time). CloudKit updates are asynchronous but will eventually sync. The app can also maintain a local dictionary of videoID→status for quick access. On app launch, it can fetch all VideoStatus records from CloudKit to initialize the seen/skipped list. Any video fetched from YouTube API that matches an existing record with status “watched/skipped” can be filtered out of the unseen feed immediately.
	•	State Management in SwiftUI: Use an ObservableObject ViewModel (e.g., FeedViewModel) that holds the list of Video models and their statuses. This view model will fetch data from YouTube, interact with CloudKit, and publish changes to the SwiftUI views. For example, when a video’s status changes, it will remove it from the “unwatched” list and SwiftUI will update the UI accordingly.

Application Architecture Overview

The app follows an MVVM (Model-View-ViewModel) architecture with these layers:
	•	Models: Channel and Video structs (as above), plus any supporting types (enums for status, etc.).
	•	ViewModels/Controllers:
	•	SubscriptionFeedViewModel – handles fetching subscription videos, sorting them, updating statuses. It interacts with the YouTube API (network calls) and CloudKit (for status). It provides published properties for the list of unseen videos.
	•	ChannelViewModel – handles loading videos for a specific channel (could reuse logic from FeedViewModel but filtered to one channel). It might fetch additional older videos for that channel on demand (for browsing history).
	•	PlayerViewModel – (if needed) to manage the playback state, though if using YT’s player SDK, it might not require much state handling except knowing the video ID to load.
	•	Views (SwiftUI):
	•	FeedView – main screen listing unseen videos across all channels.
	•	ChannelsView – list of subscribed channels (with count of unseen videos).
	•	ChannelDetailView – shows videos for a specific channel (with possibly sections for unseen vs all videos or a way to load more).
	•	VideoPlayerView – hosts the video player (YTPlayerView or AVPlayer) and playback controls.
	•	Additional UI elements: e.g., a search bar component for filtering, a toggle or segmented control to switch between “All Unwatched” vs “Skipped” vs “Watched” lists (could be an option if you want to review skipped items), etc.
	•	Navigation: Use a SwiftUI NavigationView or TabView for structure. For instance, the app might have two tabs: “Feed” and “Channels”. The Feed tab is the chronological list of new videos. The Channels tab shows all channels. From Feed, tapping a channel name or an info button could deep-link to that channel’s detail. From Channels list, tapping a channel goes to ChannelDetailView. From any list, tapping a video goes to VideoPlayerView (perhaps presented modally or pushed).
	•	CloudKit Sync Integration: The CloudKit operations (fetching records, saving statuses) will likely reside in the view model layer. On launch, we check iCloud availability and fetch existing video status records (so we know what’s already watched). This can be done with a CKQuery on the private database for all records of type Video (or a specific subscription zone, if we define one). Because CloudKit sync can also notify of changes, we might subscribe to updates (though in our case, since only one user, changes would mainly come from the user’s other devices).

User Interface Design

1. Subscription Feed Screen (Unseen Videos): This is the default view when you open the app. It presents a scrollable list of all unwatched videos from your subs:
	•	Layout: likely a SwiftUI List or LazyVStack of video rows. Each row displays the video’s thumbnail image, title, channel name, and publish date. The videos are sorted chronologically (you might choose oldest first to catch up in order, or newest first – this can be a user setting if needed, but chronological in general means by date).
	•	Each video row may have quick actions:
	•	Tapping the row opens the VideoPlayer (to start watching).
	•	A swipe action or button to “Mark as Watched” (if you want to mark it without viewing fully) or “Skip”. For example, swipe left to reveal a “Skip” action that marks the video as skipped (and removes it from the list).
	•	Possibly an icon to indicate length or other info (to help identify content). But since Shorts are filtered out, length might be uniformly longer.
	•	At the top of this screen, there can be a Filter/Search bar. Typing can filter the list in real-time by matching video titles or channel names. This helps in case the list is long and you want to find a particular video quickly.
	•	The design is focused: no extra recommendations. Just this list. If the list is empty (no unseen videos), show a friendly message like “You’re all caught up!”.

2. Channel List Screen: A view showing all your subscribed channels:
	•	Likely a simple list (or grid of icons) of channels. Each item shows the channel name (and possibly the channel’s avatar image if available via the API).
	•	You can display a count of unseen videos per channel (the app can compute this by filtering the unseen list by channel). E.g., “Channel XYZ – 5 new videos”.
	•	Channels might be sorted alphabetically or by the most recently uploaded content. A useful approach is to sort by channels that have the most unseen content or most recent uploads at top.
	•	Tapping a channel opens that channel’s detail page.

3. Channel Detail Screen: When viewing a single channel:
	•	Show the channel name and maybe banner or avatar at the top.
	•	List that channel’s videos. By default, show all recent videos from that channel, not just unseen (since the use-case includes finding an older video to show a friend). This list can be segmented or filterable:
	•	Perhaps two segments: “Unwatched” and “All Videos” for that channel. Or visually indicate which videos are watched (e.g., gray out watched ones).
	•	Include a search bar to search within that channel’s videos (useful if the channel has many videos and you recall a title keyword).
	•	The data for this list can come partly from what we’ve already fetched (unseen ones we know of) combined with on-demand fetching of older videos if the user scrolls or searches. We can use the YouTube API to get more videos from the channel’s uploads playlist if needed.
	•	From here, you can tap any video to play it. Even if it was already watched, the user might replay it (which is fine, we don’t need to change its status in that case, or we could mark re-watched if desired).

4. Video Player Screen: This is a full-screen (or pushed) view where the selected video plays:
	•	If using the YouTube iOS Player component: the UI will be a player embedded in our app. The player provides controls for play/pause, scrubbing, full-screen toggle, etc., consistent with YouTube’s experience ￼ ￼. We can overlay or place a navigation bar button to “Mark as Skipped/Watched” if the user wants to exit without finishing. However, if the user watches the video to the end, the app can automatically mark it as watched.
	•	If using AVPlayer: the VideoPlayerView could use VideoPlayer (SwiftUI’s wrapper for AVPlayer) or an AVPlayerLayer in a UIViewRepresentable. This gives the native iOS video controls. We would include an AirPlay button in this UI. We can use AVRoutePickerView integrated into SwiftUI to let the user send the video to Apple TV at any time. For instance, an AirPlay icon button on the player toolbar that, when tapped, shows available AirPlay devices (Apple TV) for streaming.
	•	Ensure AirPlay integration: Since using SwiftUI, we’ll include a UIViewRepresentable that wraps AVRoutePickerView to show the AirPlay icon. According to Apple’s docs, AVRoutePickerView provides a button for streaming to AirPlay devices. This way, even if using the YouTube web player (which might not natively show an AirPlay control), we have a consistent way for you to route audio/video to Apple TV.
	•	When a video is playing, if it finishes or if you manually mark it as watched, the view can dismiss (or offer a “Next” button to go to the next video in feed).
	•	Picture-in-Picture (PiP) could be enabled if using AVPlayer, but if using the YT web player, PiP might not be straightforward. Given this is a personal app, we can skip PiP for v1 unless you strongly want it, focusing on core functionality.

5. Skip/Watch Interaction Design: Marking a video as watched or skipped updates the state:
	•	If you watch a video fully, the app will mark it watched automatically (e.g., when playback reaches the end or you manually tap a “Mark as Watched” button). This triggers an update to CloudKit for that video’s status and removes it from the Feed list (immediately, via state update).
	•	If you choose to skip without watching, you can either swipe on the item in the feed or perhaps long-press for a context menu with “Mark as Skipped”. Once skipped, it’s treated similar to watched (removed from unseen list and status saved). Skipped might be indicated differently in channel view (maybe a different icon).
	•	There could be an “Undo” option immediately after skipping/watching in case of a mistake (not mandatory, but user-friendly).
	•	The app might also allow marking multiple videos as watched/skipped quickly (batch actions), for example if you have a backlog you want to clear. This could be a future enhancement.

YouTube API Implementation Details

API Credentials: You will create a project in Google Cloud Console with YouTube Data API enabled ￼. Use OAuth Client ID for iOS and set up the URL schemes for Google Sign-In if using Google’s library. The app will request read-only access to YouTube account info. Since this is not distributed publicly, you don’t need to worry about the sensitive scope verification, but you will still use your own account.

Fetching Data: Using Swift’s async/await, the flow might look like:
	1.	After authentication, store the access token.
	2.	Use URLSession or Google’s API client to call subscriptions?part=snippet&mine=true&maxResults=50 ￼. Parse the JSON to get channel IDs and names.
	3.	For each channel, call playlistItems.list for the uploads playlist (with a high maxResults or iterative pages) or call search.list if needed. Parse JSON for videos.
	4.	For each video, if needed, call videos.list?part=contentDetails&id= to get the duration (to filter Shorts). Alternatively, request contentDetails in the playlistItems call by including that part (if the playlistItems include duration – they might not, usually playlistItems snippet gives title, etc., and contentDetails gives videoId and publish date, not duration. Duration requires a separate videos.list query).
	5.	Filter out videos with duration less than 60s (Shorts).
	6.	Save the resulting video list in the FeedViewModel’s state and compare with CloudKit records to filter out already watched ones.

Updating Data: When a video is marked watched/skipped:
	•	Create or update the CloudKit record for that video’s status.
	•	Optionally, call YouTube’s API to mark the video as “watched” in your YouTube history (not necessary and probably not desired). Since this app is separate, you likely don’t want it to affect your official YouTube history – and the Data API doesn’t provide a direct “mark as watched” endpoint for history anyway (there is an endpoint to upload to history which is not documented for public use). We will keep the watch tracking within the app only.

Error Handling & Edge Cases:
	•	Handle network errors or API quota issues (e.g., if quota exceeded or no internet). The app should cache last known data so you’re not stuck if offline.
	•	If an API call fails for certain channels, the app could retry later. Since this is personal, a simple approach is fine (e.g., show an error toast and retry on pull-down).
	•	If Google OAuth token expires, handle refresh flow (if using GoogleSignIn SDK, it can auto-refresh; otherwise store refresh token and do a refresh token grant when needed).
	•	If iCloud is disabled or out of space (unlikely for just text records), the app should still function (perhaps default to not syncing state, or warn that statuses won’t persist). CloudKit typically won’t be an issue given tiny data footprint here.

Playing Videos on Apple TV (AirPlay vs. tvOS App)

For the first version, the simplest way to watch on Apple TV is to use AirPlay from the iOS app:
	•	The iOS video player will include an AirPlay picker button. Tapping it shows available AirPlay receivers (your Apple TV) and you can stream the video directly. This leverages Apple’s built-in AirPlay capability; no additional code on the Apple TV is needed.
	•	Ensure the AVAudioSession category allows AirPlay. If using AVPlayer/AVRoutePickerView, this is handled. If using YouTube’s player, it might rely on system AirPlay - to be safe, we will overlay our own AVRoutePickerView on top of the YT player so you can trigger AirPlay easily.
	•	With AirPlay, your phone remains the controller (you can pause/seek via the phone, or using the TV remote will send commands back).

Future tvOS app: Since you mentioned consuming on tvOS as well, we can later create a tvOS target that shares much of the code:
	•	The tvOS app would use the same CloudKit container to get the watched/skipped statuses. It could fetch videos from the API or, better, you could have the iOS app send data via CloudKit and the tvOS app mostly reads from CloudKit (to minimize duplication of API logic).
	•	SwiftUI works on tvOS, so we can reuse views (with some adaptations for focus/remote).
	•	Initially, however, implementing AirPlay might suffice. It avoids needing to navigate on the Apple TV UI – you can just pick a video on phone and AirPlay it.

Security and Privacy

Since this app is just for you, privacy concerns are limited. Still, note:
	•	Your Google OAuth tokens and any API keys should be kept secure (store in Keychain, and do not hardcode secrets in the code if it were ever shared).
	•	CloudKit private data is inherently secure and only accessible to your iCloud account ￼. We define a custom record type for video statuses, which only you (as the app user) can read/write.
	•	No user analytics or external tracking is included, aligning with the distraction-free, privacy-focused intent.

Development Timeline and Steps

To give a high-level battle plan for implementation:
	1.	Project Setup: Create an Xcode project with SwiftUI lifecycle. Enable CloudKit capability (with a default container). Add necessary frameworks: AVKit, CloudKit, etc. Set up GoogleService-Info if using GoogleSignIn or configure URL types for OAuth redirect.
	2.	YouTube API Integration: Implement OAuth flow – perhaps using ASWebAuthenticationSession to get user consent if not using Google SDK (since it’s just one user, a simple OAuth might do: open Google’s auth URL, get code, exchange for token). Once you have a token, test a simple API call to fetch subscriptions. Establish network code for calling YouTube endpoints (could use URLSession with URLComponents to build queries).
	3.	Data Models: Define Swift models for Channel and Video and an enum for VideoStatus. Set up CloudKit record representation for these (e.g., extension to convert Video to CKRecord and vice versa). In CloudKit Dashboard, define the record type “Video” with fields for ID (as name), status, title, etc.
	4.	ViewModels: Implement FeedViewModel:
	•	On init or on appear, perform subscription fetch and then video fetch for each channel. This can be done concurrently (e.g., using Task groups or async sequences).
	•	Integrate CloudKit: after fetching videos, load the CloudKit records and merge: mark any video IDs found in CloudKit as watched/skipped in the local list (and filter them out of “to display” list).
	•	Provide functions to mark a video as watched/skipped: update local state and call CloudKit save.
	5.	Views Construction: Build the SwiftUI views:
	•	FeedView: binds to FeedViewModel’s list of videos. Use List or ScrollView + LazyVStack to display video rows. Each row is a subview (VideoRowView) that displays thumbnail (use AsyncImage to load from URL), title, etc., and has onTap and swipeActions for mark watched/skip.
	•	ChannelsView: binds to list of Channel models (and maybe uses FeedViewModel to count unseen per channel). Rows navigate to ChannelDetailView.
	•	ChannelDetailView: similar to FeedView but filtered to one channel. It can use its own ViewModel or reuse FeedViewModel data filtered. Provide a way to load more videos (e.g., a “Load More” button if we didn’t fetch all history).
	•	PlayerView: If using YTPlayerView, integrate it via UIViewRepresentable. If AVPlayer, use SwiftUI VideoPlayer. Add an AirPlay button using AVRoutePickerView (wrap it and overlay or place in toolbar).
	•	Ensure the navigation links and presentation are set (possibly use .sheet for player or push navigation).
	6.	Testing Workflow: As you build, test each piece with your actual account:
	•	Sign in and fetch subscriptions -> verify you get channel list.
	•	Fetch a subset of videos -> verify filtering of shorts (maybe test on a channel that has a short).
	•	Test marking as watched -> check CloudKit Dashboard or fetch to ensure record saved.
	•	Test that after relaunch, watched videos don’t show.
	•	Test AirPlay to AppleTV (make sure the button appears and connects).
	7.	Polish: Add any additional nice-to-haves:
	•	Thumbnails caching (the system will cache via URLSession by default, or use an URLCache).
	•	Loading indicators while fetching data.
	•	Handle dark mode in SwiftUI, etc., for aesthetics.
	•	Possibly the ability to sign out or switch account (not really needed if just you).
	•	No need for App Store compliance, but still follow best practices since it’s using official APIs.

Throughout development, keep the app focused: no extraneous features. The end result is a personal “feed reader” for YouTube subscriptions that helps you deliberately choose what to watch, free of YouTube’s manipulation. By following this architecture, another AI or developer should confidently implement the app, as it clearly defines data handling, UI structure, and integration points. This plan leverages your existing tools (Google API, Premium benefits, Apple ecosystem) to ensure you spend time on quality content only, achieving the distraction-free YouTube experience you desire.

Sources:
	•	Stack Overflow – YouTube API does not provide a combined subscription feed; must list subscriptions and fetch each channel’s uploads ￼.
	•	Google Developers – OAuth required for retrieving user subscriptions (mine=true) ￼.
	•	Medium (Malsha) – Using videoDuration filters in YouTube API to exclude short videos (short <4 min) ￼.
	•	AppCoda – Demonstration of YouTube iOS helper library for embedding a YouTube player in-app ￼, which supports fullscreen playback controls ￼.
	•	Swift with Majid – CloudKit allows easy data sync across devices using the private iCloud database for each user ￼ ￼.
	•	Apple Developer Documentation – AVRoutePickerView provides an AirPlay picker button to stream video to Apple TV.