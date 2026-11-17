import Foundation

/// Represents the configured hours and minutes that divide a 24-hour day into
/// daytime (naps) and nighttime sleep.
public struct SleepScheduleConfiguration: Codable, Equatable, Sendable {
    /// Hour when nighttime sleep begins (0-23, e.g. 19 for 19:00 / 7:00 PM)
    public var nightStartHour: Int
    /// Minute when nighttime sleep begins (0-59, e.g. 0)
    public var nightStartMinute: Int
    /// Hour when daytime begins / night sleep ends (0-23, e.g. 7 for 07:00 / 7:00 AM)
    public var dayStartHour: Int
    /// Minute when daytime begins (0-59, e.g. 0)
    public var dayStartMinute: Int

    public init(
        nightStartHour: Int = 19,
        nightStartMinute: Int = 0,
        dayStartHour: Int = 7,
        dayStartMinute: Int = 0
    ) {
        self.nightStartHour = max(0, min(23, nightStartHour))
        self.nightStartMinute = max(0, min(59, nightStartMinute))
        self.dayStartHour = max(0, min(23, dayStartHour))
        self.dayStartMinute = max(0, min(59, dayStartMinute))
    }

    // MARK: - Presets

    /// Standard pediatric schedule: 19:00 (7:00 PM) to 07:00 (7:00 AM)
    public static let standard = SleepScheduleConfiguration(
        nightStartHour: 19,
        nightStartMinute: 0,
        dayStartHour: 7,
        dayStartMinute: 0
    )

    /// Early bedtime schedule: 18:30 (6:30 PM) to 06:30 (6:30 AM)
    public static let earlyBedtime = SleepScheduleConfiguration(
        nightStartHour: 18,
        nightStartMinute: 30,
        dayStartHour: 6,
        dayStartMinute: 30
    )

    /// Late bedtime schedule: 20:30 (8:30 PM) to 08:00 (8:00 AM)
    public static let lateBedtime = SleepScheduleConfiguration(
        nightStartHour: 20,
        nightStartMinute: 30,
        dayStartHour: 8,
        dayStartMinute: 0
    )

    // MARK: - Classification Logic

    /// Returns true if the given hour and minute falls within the nighttime window.
    public func isNightTime(hour: Int, minute: Int) -> Bool {
        let currentMinutes = hour * 60 + minute
        let nightMinutes = nightStartHour * 60 + nightStartMinute
        let dayMinutes = dayStartHour * 60 + dayStartMinute

        if nightMinutes > dayMinutes {
            // Normal pediatric schedule: night spans midnight (e.g. 19:00 -> 07:00)
            return currentMinutes >= nightMinutes || currentMinutes < dayMinutes
        } else if nightMinutes < dayMinutes {
            // Inverted/daytime window (e.g. night is 01:00 -> 08:00)
            return currentMinutes >= nightMinutes && currentMinutes < dayMinutes
        } else {
            // Same start & end: edge case, default to false (daytime)
            return false
        }
    }

    /// Returns true if the date falls into the nighttime sleep window.
    public func isNightTime(for date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return isNightTime(hour: hour, minute: minute)
    }

    /// Returns true if the date falls into daytime (naps window).
    public func isDayTime(for date: Date, calendar: Calendar = .current) -> Bool {
        return !isNightTime(for: date, calendar: calendar)
    }

    /// Suggests whether a sleep event should be classified as a nap or night sleep.
    public func classify(timestamp: Date, calendar: Calendar = .current) -> SleepClassification {
        return isNightTime(for: timestamp, calendar: calendar) ? .nightSleep : .nap
    }

    // MARK: - Duration Calculations

    /// Total nighttime window duration in seconds.
    public var nightWindowDuration: TimeInterval {
        let nightMinutes = nightStartHour * 60 + nightStartMinute
        let dayMinutes = dayStartHour * 60 + dayStartMinute
        let minutes: Int
        if nightMinutes > dayMinutes {
            minutes = (1440 - nightMinutes) + dayMinutes
        } else if nightMinutes < dayMinutes {
            minutes = dayMinutes - nightMinutes
        } else {
            minutes = 0
        }
        return TimeInterval(minutes * 60)
    }

    /// Total daytime window duration in seconds.
    public var dayWindowDuration: TimeInterval {
        return max(0, (24 * 3600) - nightWindowDuration)
    }

    // MARK: - Formatting Helpers

    public static func formatTime(hour: Int, minute: Int) -> String {
        return String(format: "%02d:%02d", hour, minute)
    }

    public var nightStartTimeString: String {
        Self.formatTime(hour: nightStartHour, minute: nightStartMinute)
    }

    public var dayStartTimeString: String {
        Self.formatTime(hour: dayStartHour, minute: dayStartMinute)
    }

    public static func formatDurationText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
}
