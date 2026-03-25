//
//  WPLogger.swift
//  WellPlate
//
//  Centralised, beautiful console logging for the WellPlate app.
//
//  Usage:
//    WPLogger.app.info("App launched")
//    WPLogger.network.error("Connection refused")
//    WPLogger.network.block(emoji: "📤", category: "REQUEST", id: reqId, lines: [...])
//

import OSLog
import Foundation

// MARK: - WPLogger

/// Namespace for all WellPlate logging channels.
/// All output is DEBUG-only and routes through `os.Logger` for Xcode / Console.app filtering.
enum WPLogger {

    // MARK: Channels
    static let app        = Channel(category: "App",      icon: "🏠")
    static let network    = Channel(category: "Network",  icon: "🌐")
    static let nutrition  = Channel(category: "Nutrition",icon: "🥗")
    static let barcode    = Channel(category: "Barcode",  icon: "📷")
    static let home       = Channel(category: "Home",     icon: "📋")
    static let stress     = Channel(category: "Stress",   icon: "🧘")
    static let healthKit  = Channel(category: "HealthKit",icon: "❤️")
    static let ui         = Channel(category: "UI",       icon: "🎨")
    static let speech     = Channel(category: "Speech",   icon: "🎙️")

    // MARK: - Box width constant
    private static let boxWidth = 62

    // MARK: - Channel

    struct Channel {
        let category: String
        let icon: String
        private let logger: Logger

        init(category: String, icon: String) {
            self.category = category
            self.icon = icon
            self.logger = Logger(subsystem: "com.wellplate.app", category: category)
        }

        // MARK: Single-line events

        func debug(_ message: String) {
            #if DEBUG
            let line = "🔍  [\(category)]  \(message)"
            logger.debug("\(line, privacy: .public)")
            #endif
        }

        func info(_ message: String) {
            #if DEBUG
            let line = "ℹ️   [\(category)]  \(message)"
            logger.info("\(line, privacy: .public)")
            #endif
        }

        func warning(_ message: String) {
            #if DEBUG
            let line = "⚠️  [\(category)]  \(message)"
            logger.warning("\(line, privacy: .public)")
            #endif
        }

        func error(_ message: String) {
            #if DEBUG
            let line = "❌  [\(category)]  \(message)"
            logger.error("\(line, privacy: .public)")
            #endif
        }

        // MARK: Block events (box-drawing)

        /// Renders a beautiful `┌─── │ └───` block in the console.
        ///
        /// - Parameters:
        ///   - emoji:    Leading emoji on the header line (e.g. `"📤"`, `"✅"`, `"❌"`)
        ///   - category: Short label after the emoji (e.g. `"REQUEST"`, `"GROQ RESPONSE"`)
        ///   - id:       Optional unique ID suffix for correlating request/response pairs
        ///   - lines:    Body lines rendered between `│` borders
        func block(emoji: String, title: String, id: String? = nil, lines: [String]) {
            #if DEBUG
            let totalWidth = WPLogger.boxWidth
            let idSuffix   = id.map { " [\($0)]" } ?? ""
            let header     = "\(emoji) \(category.uppercased()) · \(title)\(idSuffix)"
            let dashCount  = max(4, totalWidth - header.count - 5) // "┌─── " + " " padding
            let topBorder  = "┌─── \(header) " + String(repeating: "─", count: dashCount)
            let botBorder  = "└" + String(repeating: "─", count: totalWidth - 1)

            var output = topBorder
            for line in lines {
                output += "\n│  \(line)"
            }
            output += "\n\(botBorder)"
            logger.debug("\(output, privacy: .public)")
            print(output) // also echo to Xcode debug console stream
            #endif
        }
    }
}
