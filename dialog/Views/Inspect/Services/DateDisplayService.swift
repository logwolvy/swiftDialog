//
//  DateDisplayService.swift
//  dialog
//
//  Created by Claude on 2026-03-14
//
//  Global date formatting service for presets 5 & 6
//  Supports relative, short, medium, long, and iso8601 styles with locale awareness
//

import Foundation

/// Global date formatting service for consistent date display across presets
/// Configured via `dateStyle` in InspectConfig JSON
final class DateDisplayService {
    static let shared = DateDisplayService()

    private var style: DateStyle = .medium

    /// Supported date formatting styles
    enum DateStyle: String, CaseIterable {
        case relative   // "2 hours ago" / "vor 2 Stunden"
        case short      // "3/14/26, 3:45 PM" / "14.03.26, 15:45"
        case medium     // "Mar 14, 2026, 3:45 PM" / "14. März 2026, 15:45" (default)
        case long       // "March 14, 2026 at 3:45 PM" / "14. März 2026 um 15:45"
        case iso8601    // "2026-03-14T15:45:00Z" (locale-independent)
    }

    // MARK: - Cached Formatters (for performance)

    private lazy var shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var mediumFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var longFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private lazy var relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // Legacy formatters for parsing plist date strings
    private lazy var legacyParsers: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm:ss",
            "dd.MM.yyyy HH:mm:ss"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }()

    private init() {}

    // MARK: - Configuration

    /// Configure the service with a style from config
    /// - Parameter styleString: The style string from InspectConfig.dateStyle (nil defaults to "medium")
    func configure(style styleString: String?) {
        self.style = DateStyle(rawValue: styleString ?? "medium") ?? .medium
        writeLog("DateDisplayService: Configured with style '\(self.style.rawValue)'", logLevel: .info)
    }

    /// Get the current configured style
    var currentStyle: DateStyle {
        return style
    }

    // MARK: - Formatting

    /// Format a Date using the configured style
    /// - Parameter date: The Date to format
    /// - Returns: Formatted date string according to current style and locale
    func format(_ date: Date) -> String {
        switch style {
        case .relative:
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        case .short:
            return shortFormatter.string(from: date)
        case .medium:
            return mediumFormatter.string(from: date)
        case .long:
            return longFormatter.string(from: date)
        case .iso8601:
            return iso8601Formatter.string(from: date)
        }
    }

    // MARK: - Parsing

    /// Parse a value (typically from plist) into a Date
    /// - Parameter value: The value to parse (String, Date, or NSNumber timestamp)
    /// - Returns: Parsed Date, or nil if parsing fails
    func parse(_ value: Any?) -> Date? {
        guard let value = value else { return nil }

        // Already a Date
        if let date = value as? Date {
            return date
        }

        // String date formats
        if let stringValue = value as? String {
            // Try ISO8601 first
            if let date = iso8601Formatter.date(from: stringValue) {
                return date
            }

            // Try legacy formats
            for parser in legacyParsers {
                if let date = parser.date(from: stringValue) {
                    return date
                }
            }

            return nil
        }

        // Unix timestamp (seconds since 1970)
        if let timestamp = value as? TimeInterval {
            return Date(timeIntervalSince1970: timestamp)
        }

        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }

        return nil
    }

    /// Parse a value and format it, with fallback
    /// - Parameters:
    ///   - value: The value to parse
    ///   - fallback: Fallback string if parsing fails (default: "Never")
    /// - Returns: Formatted date string or fallback
    func parseAndFormat(_ value: Any?, fallback: String = "Never") -> String {
        guard let date = parse(value) else {
            return fallback
        }
        return format(date)
    }
}
