//
//  FeedViewModel.swift
//  MeTube
//
//  ViewModel for the subscription feed using the MeTube backend API (API.md)
//  Channels and videos are kept in memory and refreshed on demand.
//  Video state (watched/skipped/playhead) is stored in CloudKit via StatusSyncManager.
//

import Combine
import Foundation
import SwiftData

// MARK: - Loading State

enum LoadingState: Equatable {
    case idle
    case refreshing

    var description: String {
        switch self {
        case .idle:
            return ""
        case .refreshing:
            return "Refreshing feed..."
        }
    }

    var isLoading: Bool {
        self != .idle
    }
}

/// ViewModel for managing the subscription feed.
@MainActor
final class FeedViewModel: ObservableObject {
    // MARK: - Published

    @Published var channels: [Channel] = []
    @Published var allVideos: [Video] = []
    @Published var loadingState: LoadingState = .idle
    @Published var error: String?
    @Published var searchText: String = ""
    @Published var selectedStatus: VideoStatus? = .unwatched

    var isLoading: Bool { loadingState.isLoading }

    // MARK: - Computed

    var filteredVideos: [Video] {
        var result = allVideos

        if let status = selectedStatus {
            result = result.filter { $0.status == status }
        }

        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { video in
                video.title.lowercased().contains(lowercasedSearch) ||
                video.channelName.lowercased().contains(lowercasedSearch)
            }
        }

        return result.sorted { $0.publishedDate > $1.publishedDate }
    }

    var unwatchedVideos: [Video] {
        allVideos.filter { $0.status == .unwatched }
            .sorted { $0.publishedDate > $1.publishedDate }
    }

    func unwatchedCount(for channelId: String) -> Int {
        allVideos.filter { $0.channelId == channelId && $0.status == .unwatched }.count
    }

    func videos(for channelId: String) -> [Video] {
        allVideos.filter { $0.channelId == channelId }
            .sorted { $0.publishedDate > $1.publishedDate }
    }

    // MARK: - Services

    private let apiService: MeTubeAPIService
    private let statusRepository: StatusRepository
    private let statusSyncManager: StatusSyncManager

    // MARK: - Cache / Concurrency

    private var statusCache: [String: StatusEntity] = [:]
    private var isRefreshing = false

    // MARK: - Sequence Watermark

    private enum WatermarkKey {
        static let lastMaxSeq = "MeTube.lastMaxSeq"
    }

    private var lastMaxSeq: Int {
        get { UserDefaults.standard.integer(forKey: WatermarkKey.lastMaxSeq) }
        set { UserDefaults.standard.set(newValue, forKey: WatermarkKey.lastMaxSeq) }
    }

    // MARK: - Init

    init(modelContext: ModelContext, apiService: MeTubeAPIService = MeTubeAPIService()) {
        self.apiService = apiService
        self.statusRepository = StatusRepository(modelContext: modelContext)
        self.statusSyncManager = StatusSyncManager(statusRepository: statusRepository)

        Task {
            await reloadStatusCache()
        }
    }

    // MARK: - Refreshing

    /// Called when the app becomes active (cold start or foreground transition).
    func refreshOnForeground() async {
        await refresh(forceFull: allVideos.isEmpty)
    }

    /// Refresh channels and videos from the backend.
    /// - Parameter forceFull: When true, discards in-memory videos and refetches everything.
    func refresh(forceFull: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        error = nil
        loadingState = .refreshing

        let isFull = forceFull || allVideos.isEmpty
        let afterSeq = isFull ? 0 : lastMaxSeq

        let statusSyncTask = Task { @MainActor in
            do {
                _ = try await statusSyncManager.syncIfNeeded()
            } catch {
                appLog("Status sync failed (non-fatal): \(error)", category: .cloudKit, level: .warning)
            }
        }

        do {
            async let channelsTask = apiService.fetchAllChannels()
            async let videosTask = fetchAllVideos(afterSeq: afterSeq)

            let channelDTOs = try await channelsTask
            let (videoDTOs, maxSeqReturned) = try await videosTask

            let newChannels = channelDTOs
                .map { Channel(id: $0.channelId, name: ($0.title.trimmedNonEmpty) ?? $0.channelId) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let channelNameById = Dictionary(uniqueKeysWithValues: newChannels.map { ($0.id, $0.name) })

            if isFull {
                allVideos = mapVideos(videoDTOs, channelNameById: channelNameById, statusCache: statusCache)
            } else {
                let existingIds = Set(allVideos.map { $0.id })
                let mapped = mapVideos(videoDTOs, channelNameById: channelNameById, statusCache: statusCache)
                let newOnes = mapped.filter { !existingIds.contains($0.id) }
                if !newOnes.isEmpty {
                    allVideos.append(contentsOf: newOnes)
                }
            }

            channels = newChannels

            if maxSeqReturned > lastMaxSeq {
                lastMaxSeq = maxSeqReturned
            }

            _ = await statusSyncTask.result
            await reloadStatusCache()
            applyStatusesToInMemoryVideos()

            loadingState = .idle
            appLog("Feed refresh completed (afterSeq=\(afterSeq), received=\(videoDTOs.count), maxSeq=\(lastMaxSeq))", category: .feed, level: .success)
        } catch {
            loadingState = .idle
            self.error = error.localizedDescription
            appLog("Feed refresh failed: \(error)", category: .feed, level: .error)
        }
    }

    func resetAndRefresh() async {
        lastMaxSeq = 0
        allVideos = []
        channels = []
        await refresh(forceFull: true)
    }

    // MARK: - Backend Fetching

    private func fetchAllVideos(afterSeq: Int) async throws -> ([MeTubeVideoDTO], Int) {
        let limit = MeTubeAPIConfig.defaultVideoLimit
        var collected: [MeTubeVideoDTO] = []
        var currentAfter = max(0, afterSeq)
        var maxSeqSeen = afterSeq

        while true {
            let response = try await apiService.queryVideos(afterSeq: currentAfter, limit: limit)

            if response.maxSeqReturned > maxSeqSeen {
                maxSeqSeen = response.maxSeqReturned
            }

            guard !response.videos.isEmpty else {
                break
            }

            collected.append(contentsOf: response.videos)

            if response.videos.count < limit || response.maxSeqReturned <= currentAfter {
                break
            }

            currentAfter = response.maxSeqReturned
        }

        return (collected, maxSeqSeen)
    }

    private func mapVideos(
        _ dtos: [MeTubeVideoDTO],
        channelNameById: [String: String],
        statusCache: [String: StatusEntity]
    ) -> [Video] {
        dtos.map { dto in
            let status = statusCache[dto.videoId]?.watchStatus.toVideoStatus() ?? .unwatched
            return Video(
                id: dto.videoId,
                title: dto.title,
                channelId: dto.channelId,
                channelName: channelNameById[dto.channelId] ?? "",
                publishedDate: dto.publishedAt,
                duration: 0,
                thumbnailURL: YouTubeThumbnail.url(for: dto.videoId),
                description: nil,
                status: status
            )
        }
    }

    // MARK: - Status Cache

    private func reloadStatusCache() async {
        do {
            let statusEntities = try statusRepository.fetchAllStatuses()
            statusCache = statusEntities.reduce(into: [:]) { $0[$1.videoId] = $1 }
        } catch {
            appLog("Failed to load cached statuses: \(error)", category: .cloudKit, level: .warning)
        }
    }

    private func applyStatusesToInMemoryVideos() {
        guard !allVideos.isEmpty else { return }
        for index in allVideos.indices {
            let videoId = allVideos[index].id
            allVideos[index].status = statusCache[videoId]?.watchStatus.toVideoStatus() ?? .unwatched
        }
    }

    // MARK: - Status Management

    func loadVideoStatuses() async {
        appLog("loadVideoStatuses called", category: .feed, level: .debug)
        await reloadStatusCache()
        applyStatusesToInMemoryVideos()
    }

    func getPlaybackPosition(for videoId: String) -> TimeInterval {
        do {
            return try statusRepository.getPlaybackPosition(forVideoId: videoId)
        } catch {
            appLog("Error getting playback position: \(error)", category: .feed, level: .error)
            return 0
        }
    }

    func savePlaybackPosition(for videoId: String, position: TimeInterval) {
        do {
            let updated = try statusRepository.updatePlaybackPosition(forVideoId: videoId, position: position)
            statusCache[videoId] = updated
            appLog("Saved playback position for \(videoId): \(position)s", category: .feed, level: .debug)

            Task { @MainActor in
                do {
                    _ = try await statusSyncManager.syncIfNeeded()
                } catch {
                    appLog("Background status sync failed: \(error)", category: .cloudKit, level: .error)
                }
            }
        } catch {
            appLog("Error saving playback position: \(error)", category: .feed, level: .error)
        }
    }

    func markAsWatched(_ video: Video) async {
        appLog("Marking video as watched: \(video.title)", category: .feed, level: .info)
        await updateVideoStatus(video, newStatus: .watched)
    }

    func markAsSkipped(_ video: Video) async {
        appLog("Marking video as skipped: \(video.title)", category: .feed, level: .info)
        await updateVideoStatus(video, newStatus: .skipped)
    }

    func markAsUnwatched(_ video: Video) async {
        appLog("Marking video as unwatched: \(video.title)", category: .feed, level: .info)
        await updateVideoStatus(video, newStatus: .unwatched)
    }

    private func updateVideoStatus(_ video: Video, newStatus: VideoStatus) async {
        do {
            let updated = try statusRepository.updateStatus(
                forVideoId: video.id,
                status: newStatus.toWatchStatus(),
                synced: false
            )
            statusCache[video.id] = updated

            if let index = allVideos.firstIndex(where: { $0.id == video.id }) {
                allVideos[index].status = newStatus
            }

            Task { @MainActor in
                do {
                    _ = try await statusSyncManager.syncIfNeeded()
                } catch {
                    appLog("Background status sync failed: \(error)", category: .cloudKit, level: .error)
                }
            }

            appLog("Updated video status locally: \(video.id) -> \(newStatus)", category: .feed, level: .success)
        } catch {
            appLog("Error updating video status: \(error)", category: .feed, level: .error)
            self.error = "Failed to update video status"
        }
    }

    func markChannelAsWatched(_ channelId: String) async {
        let channelVideos = allVideos.filter { $0.channelId == channelId && $0.status == .unwatched }
        for video in channelVideos {
            await markAsWatched(video)
        }
    }

    // MARK: - Utility

    func clearError() {
        error = nil
    }
}

// MARK: - Helpers

private enum YouTubeThumbnail {
    static func url(for videoId: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return value.isEmpty ? nil : value
    }
}
