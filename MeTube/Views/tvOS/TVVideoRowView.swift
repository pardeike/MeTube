//
//  TVVideoRowView.swift
//  MeTube
//
//  tvOS-specific video row view with larger thumbnails and focus support
//

import SwiftUI

#if os(tvOS)
struct TVVideoRowView: View {
    let video: Video
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Large Thumbnail for TV
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: video.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(1.5)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "play.rectangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 400, height: 225) // 16:9 for TV
                .clipped()
                .cornerRadius(12)
                
                // Duration Badge
                Text(video.durationString)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(6)
                    .padding(8)
            }
            
            // Video Info
            VStack(alignment: .leading, spacing: 12) {
                Text(video.title)
                    .font(.title3)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(video.channelName)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(video.relativePublishDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Status indicator
                if video.status != .unwatched {
                    HStack(spacing: 8) {
                        Image(systemName: video.status == .watched ? "checkmark.circle.fill" : "forward.fill")
                            .font(.headline)
                        Text(video.status == .watched ? "Watched" : "Skipped")
                            .font(.headline)
                    }
                    .foregroundColor(video.status == .watched ? .green : .orange)
                    .padding(.top, 8)
                }
            }
            .padding(.vertical, 8)
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
        .cornerRadius(16)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .opacity(video.status == .unwatched ? 1.0 : 0.7)
    }
}

/// A simpler card-style video view for tvOS grid layouts
struct TVVideoCardView: View {
    let video: Video
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: video.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(ProgressView())
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "play.rectangle")
                                    .font(.title)
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 300, height: 169) // 16:9
                .clipped()
                .cornerRadius(8)
                
                // Duration
                Text(video.durationString)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(4)
                    .padding(6)
            }
            
            // Title
            Text(video.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(2)
            
            // Channel
            Text(video.channelName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 300)
        .opacity(video.status == .unwatched ? 1.0 : 0.6)
    }
}

#Preview {
    VStack {
        TVVideoCardView(video: Video(
            id: "test1",
            title: "This is a sample video title",
            channelId: "channel1",
            channelName: "Sample Channel",
            publishedDate: Date().addingTimeInterval(-3600),
            duration: 612,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"),
            status: .unwatched
        ))
    }
    .padding()
    .background(Color.black)
}
#endif
