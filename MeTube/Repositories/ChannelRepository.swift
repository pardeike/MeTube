//
//  ChannelRepository.swift
//  MeTube
//
//  Repository for channel CRUD operations in the local database
//

import Foundation
import SwiftData

/// Repository for managing channels in the local SwiftData database
@MainActor
class ChannelRepository {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all channels from the local database
    func fetchAllChannels() throws -> [ChannelEntity] {
        let descriptor = FetchDescriptor<ChannelEntity>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch a channel by its ID
    func fetchChannel(byId channelId: String) throws -> ChannelEntity? {
        let predicate = #Predicate<ChannelEntity> { channel in
            channel.channelId == channelId
        }
        let descriptor = FetchDescriptor<ChannelEntity>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    // MARK: - Save Operations
    
    /// Save or update a channel in the database
    /// - Parameter channel: The channel entity to save
    /// - Returns: The saved channel entity
    @discardableResult
    func saveChannel(_ channel: ChannelEntity) throws -> ChannelEntity {
        // Check if channel already exists
        // Don't use try? here - we need to know if the fetch actually failed
        let existingChannel = try fetchChannel(byId: channel.channelId)
        
        if let existingChannel = existingChannel {
            // Update existing channel
            existingChannel.name = channel.name
            existingChannel.thumbnailURL = channel.thumbnailURL
            existingChannel.channelDescription = channel.channelDescription
            existingChannel.uploadsPlaylistId = channel.uploadsPlaylistId
            existingChannel.lastModified = Date()
            existingChannel.synced = channel.synced
            
            try modelContext.save()
            return existingChannel
        } else {
            // Insert new channel
            modelContext.insert(channel)
            try modelContext.save()
            return channel
        }
    }
    
    /// Save multiple channels in a batch
    func saveChannels(_ channels: [ChannelEntity]) throws {
        // Deduplicate channels by channelId to prevent inserting duplicates
        var seenIds = Set<String>()
        let uniqueChannels = channels.filter { channel in
            if seenIds.contains(channel.channelId) {
                return false
            }
            seenIds.insert(channel.channelId)
            return true
        }
        
        for channel in uniqueChannels {
            try saveChannel(channel)
        }
    }
    
    // MARK: - Delete Operations
    
    /// Delete a channel by its ID
    func deleteChannel(byId channelId: String) throws {
        if let channel = try fetchChannel(byId: channelId) {
            modelContext.delete(channel)
            try modelContext.save()
        }
    }
    
    /// Delete all channels
    func deleteAllChannels() throws {
        let channels = try fetchAllChannels()
        for channel in channels {
            modelContext.delete(channel)
        }
        try modelContext.save()
    }
    
    // MARK: - Utility
    
    /// Count total number of channels
    func count() throws -> Int {
        let descriptor = FetchDescriptor<ChannelEntity>()
        return try modelContext.fetchCount(descriptor)
    }
}
