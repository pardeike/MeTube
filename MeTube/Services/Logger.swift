//
//  Logger.swift
//  MeTube
//
//  Centralized logging service for debugging
//

import Foundation
import os.log

/// Configuration for logging
enum LogConfig {
    /// Master switch to enable/disable all logging
    static var isEnabled: Bool = true
    
    /// Enable verbose logging for extra details
    static var isVerbose: Bool = true
    
    /// Log categories that can be individually toggled
    struct Categories {
        static var auth: Bool = true
        static var feed: Bool = true
        static var cloudKit: Bool = true
        static var youtube: Bool = true
        static var player: Bool = true
        static var ui: Bool = true
        static var persistence: Bool = true
    }
}

/// Log levels for categorizing messages
enum LogLevel: String {
    case debug = "🔍 DEBUG"
    case info = "ℹ️ INFO"
    case warning = "⚠️ WARNING"
    case error = "❌ ERROR"
    case success = "✅ SUCCESS"
}

/// Log categories for filtering
enum LogCategory: String {
    case auth = "AUTH"
    case feed = "FEED"
    case cloudKit = "CLOUDKIT"
    case youtube = "YOUTUBE"
    case player = "PLAYER"
    case ui = "UI"
    case persistence = "PERSISTENCE"
    
    var isEnabled: Bool {
        switch self {
        case .auth: return LogConfig.Categories.auth
        case .feed: return LogConfig.Categories.feed
        case .cloudKit: return LogConfig.Categories.cloudKit
        case .youtube: return LogConfig.Categories.youtube
        case .player: return LogConfig.Categories.player
        case .ui: return LogConfig.Categories.ui
        case .persistence: return LogConfig.Categories.persistence
        }
    }
}

/// Centralized logger for the app
final class AppLogger {
    static let shared = AppLogger()
    
    private let osLog = OSLog(subsystem: "com.metube.app", category: "MeTube")
    private let dateFormatter: DateFormatter
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    /// Log a message with category, level, and optional details
    func log(_ message: String, category: LogCategory, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard LogConfig.isEnabled && category.isEnabled else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let location = LogConfig.isVerbose ? " [\(fileName):\(line) \(function)]" : ""
        
        let logMessage = "[\(timestamp)] [\(category.rawValue)] \(level.rawValue): \(message)\(location)"
        
        // Log to system log (unified logging) - this also outputs to Console and Xcode
        let osLogType: OSLogType
        switch level {
        case .debug: osLogType = .debug
        case .info: osLogType = .info
        case .warning: osLogType = .default
        case .error: osLogType = .error
        case .success: osLogType = .info
        }
        os_log("%{public}@", log: osLog, type: osLogType, logMessage)
    }
    
    /// Log with context data (dictionary)
    func log(_ message: String, category: LogCategory, level: LogLevel = .info, context: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
        guard LogConfig.isEnabled && category.isEnabled else { return }
        
        var contextString = ""
        if LogConfig.isVerbose && !context.isEmpty {
            let contextItems = context.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
            contextString = "\n\(contextItems)"
        }
        
        log("\(message)\(contextString)", category: category, level: level, file: file, function: function, line: line)
    }
}

// MARK: - Convenience Functions

/// Global logging function for quick access
func appLog(_ message: String, category: LogCategory, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.log(message, category: category, level: level, file: file, function: function, line: line)
}

/// Global logging function with context
func appLog(_ message: String, category: LogCategory, level: LogLevel = .info, context: [String: Any], file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.log(message, category: category, level: level, context: context, file: file, function: function, line: line)
}
