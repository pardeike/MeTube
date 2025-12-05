//
//  VideoRowView.swift
//  MeTube
//
//  Row view for displaying a video in a list
//

import SwiftUI

struct VideoRowView: View {
    let video: Video
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: video.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fit)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(
                                Image(systemName: "play.rectangle")
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fit)
                    }
                }
                .frame(width: 160)
                .cornerRadius(8)
                
                // Duration Badge
                Text(video.durationString)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(4)
                    .padding(4)
            }
            
            // Video Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(video.channelName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(video.relativePublishDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Status indicator
                if video.status != .unwatched {
                    HStack(spacing: 4) {
                        Image(systemName: video.status == .watched ? "checkmark.circle.fill" : "forward.fill")
                            .font(.caption2)
                        Text(video.status == .watched ? "Watched" : "Skipped")
                            .font(.caption2)
                    }
                    .foregroundColor(video.status == .watched ? .green : .orange)
                    .padding(.top, 2)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(video.status == .unwatched ? 1.0 : 0.6)
    }
}

#Preview {
    List {
        VideoRowView(video: Video(
            id: "test1",
            title: "This is a sample video title that could be very long",
            channelId: "channel1",
            channelName: "Sample Channel",
            publishedDate: Date().addingTimeInterval(-3600),
            duration: 612,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"),
            status: .unwatched
        ))
        
        VideoRowView(video: Video(
            id: "test2",
            title: "Another video that has been watched",
            channelId: "channel2",
            channelName: "Another Channel",
            publishedDate: Date().addingTimeInterval(-86400),
            duration: 3720,
            thumbnailURL: nil,
            status: .watched
        ))
        
        VideoRowView(video: Video(
            id: "test3",
            title: "Skipped video example",
            channelId: "channel3",
            channelName: "Third Channel",
            publishedDate: Date().addingTimeInterval(-172800),
            duration: 180,
            thumbnailURL: nil,
            status: .skipped
        ))
    }
    .listStyle(.plain)
}
