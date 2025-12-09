//
//  PlatformUtilities.swift
//  MeTube
//
//  Cross-platform utilities for iOS and tvOS support
//

import Foundation
import SwiftUI

// MARK: - Platform Detection

/// Utility enum for cross-platform code
enum Platform {
    /// Returns true if running on tvOS
    static var isTVOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }
    
    /// Returns true if running on iOS
    static var isIOS: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    
    /// Current platform name for logging
    static var name: String {
        #if os(tvOS)
        return "tvOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - Cross-Platform View Modifiers

/// A view modifier that applies different modifiers based on platform
struct PlatformViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .focusable()
        #else
        content
        #endif
    }
}

extension View {
    /// Apply platform-specific view modifications
    func platformStyle() -> some View {
        self.modifier(PlatformViewModifier())
    }
}

// MARK: - Navigation Style Helpers

/// Cross-platform navigation style
struct PlatformNavigationStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .navigationBarHidden(false)
        #else
        content
        #endif
    }
}

extension View {
    func platformNavigationStyle() -> some View {
        self.modifier(PlatformNavigationStyle())
    }
}

// MARK: - Screen Size Utilities

enum ScreenSize {
    /// Get appropriate thumbnail size based on platform
    static var videoThumbnailWidth: CGFloat {
        #if os(tvOS)
        return 400 // Larger thumbnails for TV
        #else
        return 160
        #endif
    }
    
    /// Get appropriate thumbnail height based on platform
    static var videoThumbnailHeight: CGFloat {
        #if os(tvOS)
        return 225 // 16:9 aspect ratio
        #else
        return 90
        #endif
    }
    
    /// Get appropriate font size for titles
    static var titleFontSize: CGFloat {
        #if os(tvOS)
        return 28
        #else
        return 17 // Default subheadline
        #endif
    }
    
    /// Get channel thumbnail size
    static var channelThumbnailSize: CGFloat {
        #if os(tvOS)
        return 100
        #else
        return 50
        #endif
    }
}

// MARK: - Gesture Utilities

/// Cross-platform gesture handling
enum GestureConfig {
    /// Whether swipe gestures are supported (not on tvOS)
    static var supportsSwipeGestures: Bool {
        #if os(tvOS)
        return false
        #else
        return true
        #endif
    }
    
    /// Minimum tap target size for the platform
    static var minimumTapTargetSize: CGFloat {
        #if os(tvOS)
        return 66 // tvOS requires larger touch targets
        #else
        return 44 // iOS standard
        #endif
    }
}
