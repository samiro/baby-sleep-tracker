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

    // MARK: - 24-Hour Cycle Boundaries

    /// Returns the 24-hour cycle `[start, end)` containing `date`, anchored at `nightStartHour:nightStartMinute`.
    public func cycleRange(containing date: Date, calendar: Calendar = .current) -> SleepCycleRange {
        let startOfCalendarDay = calendar.startOfDay(for: date)
        let todayCycleStart = Self.dateOnCalendarDay(
            startOfCalendarDay,
            hour: nightStartHour,
            minute: nightStartMinute,
            calendar: calendar
        )

        let cycleStartDay: Date
        let cycleStart: Date
        if date >= todayCycleStart {
            cycleStartDay = startOfCalendarDay
            cycleStart = todayCycleStart
        } else {
            let prevDay = calendar.date(byAdding: .day, value: -1, to: startOfCalendarDay) ?? startOfCalendarDay
            cycleStartDay = prevDay
            cycleStart = Self.dateOnCalendarDay(
                prevDay,
                hour: nightStartHour,
                minute: nightStartMinute,
                calendar: calendar
            )
        }

        let nextDay = calendar.date(byAdding: .day, value: 1, to: cycleStartDay) ?? cycleStartDay
        let cycleEnd = Self.dateOnCalendarDay(
            nextDay,
            hour: nightStartHour,
            minute: nightStartMinute,
            calendar: calendar
        )

        let cycleDayStart = Self.dayStartInsideCycle(
            cycleStartDay: cycleStartDay,
            nextDay: nextDay,
            nightStartHour: nightStartHour,
            nightStartMinute: nightStartMinute,
            dayStartHour: dayStartHour,
            dayStartMinute: dayStartMinute,
            calendar: calendar
        )

        return SleepCycleRange(start: cycleStart, end: cycleEnd, dayStart: cycleDayStart)
    }

    /// Returns the 24-hour cycle shifted by `offset` cycles from the cycle containing `referenceDate`
    /// (`0` = current cycle, `-1` = previous cycle, etc.).
    public func cycleRange(
        offset: Int,
        from referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> SleepCycleRange {
        let base = cycleRange(containing: referenceDate, calendar: calendar)
        guard offset != 0 else { return base }

        let baseStartDay = calendar.startOfDay(for: base.start)
        let targetStartDay = calendar.date(byAdding: .day, value: offset, to: baseStartDay) ?? baseStartDay
        let targetNextDay = calendar.date(byAdding: .day, value: 1, to: targetStartDay) ?? targetStartDay

        let start = Self.dateOnCalendarDay(
            targetStartDay,
            hour: nightStartHour,
            minute: nightStartMinute,
            calendar: calendar
        )
        let end = Self.dateOnCalendarDay(
            targetNextDay,
            hour: nightStartHour,
            minute: nightStartMinute,
            calendar: calendar
        )
        let cycleDayStart = Self.dayStartInsideCycle(
            cycleStartDay: targetStartDay,
            nextDay: targetNextDay,
            nightStartHour: nightStartHour,
            nightStartMinute: nightStartMinute,
            dayStartHour: dayStartHour,
            dayStartMinute: dayStartMinute,
            calendar: calendar
        )

        return SleepCycleRange(start: start, end: end, dayStart: cycleDayStart)
    }

    /// Returns the non-positive cycle offset (`0` = current cycle, `-1` = previous cycle, etc.)
    /// for the 24-hour cycle containing `targetDate` relative to `referenceDate`.
    public func cycleOffset(
        for targetDate: Date,
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let currentCycle = cycleRange(containing: referenceDate, calendar: calendar)
        let targetCycle = cycleRange(containing: targetDate, calendar: calendar)
        let currentStartDay = calendar.startOfDay(for: currentCycle.start)
        let targetStartDay = calendar.startOfDay(for: targetCycle.start)
        let deltaDays = calendar.dateComponents([.day], from: currentStartDay, to: targetStartDay).day ?? 0
        return min(0, deltaDays)
    }

    /// Returns cross-cycle metadata when `interval` starts in one 24-hour cycle and extends into a later cycle,
    /// regardless of whether it is a nap or night sleep. Returns `nil` when the interval stays within a single cycle.
    public func crossCycleInfo(
        for interval: SleepInterval,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CrossCycleIntervalInfo? {
        let effectiveEnd = interval.endTime ?? now
        guard effectiveEnd > interval.startTime else { return nil }

        let startCycle = cycleRange(containing: interval.startTime, calendar: calendar)
        guard effectiveEnd > startCycle.end else { return nil }

        let endCycleReference = effectiveEnd.addingTimeInterval(-1)
        let endCycle = cycleRange(containing: endCycleReference, calendar: calendar)
        guard startCycle != endCycle else { return nil }

        let totalDuration = max(0, effectiveEnd.timeIntervalSince(interval.startTime))
        return CrossCycleIntervalInfo(
            interval: interval,
            startCycle: startCycle,
            endCycle: endCycle,
            totalDuration: totalDuration,
            isOngoing: !interval.isCompleted
        )
    }

    private static func dateOnCalendarDay(
        _ calendarDay: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: calendarDay)
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? calendarDay
    }

    private static func dayStartInsideCycle(
        cycleStartDay: Date,
        nextDay: Date,
        nightStartHour: Int,
        nightStartMinute: Int,
        dayStartHour: Int,
        dayStartMinute: Int,
        calendar: Calendar
    ) -> Date {
        let nightMinutes = nightStartHour * 60 + nightStartMinute
        let dayMinutes = dayStartHour * 60 + dayStartMinute
        let targetDay = nightMinutes > dayMinutes ? nextDay : cycleStartDay
        return dateOnCalendarDay(
            targetDay,
            hour: dayStartHour,
            minute: dayStartMinute,
            calendar: calendar
        )
    }
}

/// Represents a half-open 24-hour sleep cycle `[start, end)` defined by the user's schedule configuration.
public struct SleepCycleRange: Equatable, Sendable {
    /// Inclusive start of the cycle (e.g. Day D at 19:00:00).
    public let start: Date
    /// Exclusive end of the cycle (e.g. Day D+1 at 19:00:00).
    public let end: Date
    /// Timestamp within `[start, end)` where the daytime window starts (e.g. Day D+1 at 07:00:00).
    public let dayStart: Date

    public init(start: Date, end: Date, dayStart: Date? = nil) {
        self.start = start
        self.end = end
        self.dayStart = dayStart ?? start
    }

    /// Inclusive last minute of the cycle for display purposes (e.g. 18:59 when `end` is 19:00).
    public var displayEnd: Date {
        end.addingTimeInterval(-60)
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Primary navigation label for the cycle in History (e.g. "Ciclo actual (24h)", "Ciclo anterior", or date span).
    public func navigationTitle(
        forOffset offset: Int,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        switch offset {
        case 0:
            return "Ciclo actual"
        case -1:
            return "Ciclo anterior"
        default:
            let dayFormatter = DateFormatter()
            dayFormatter.calendar = calendar
            dayFormatter.timeZone = calendar.timeZone
            dayFormatter.locale = locale
            dayFormatter.dateFormat = "d MMM"

            let startStr = dayFormatter.string(from: start)
            let endStr = dayFormatter.string(from: displayEnd)
            if calendar.isDate(start, inSameDayAs: displayEnd) {
                return startStr
            } else {
                return "\(startStr) – \(endStr)"
            }
        }
    }

    /// Secondary navigation subtitle showing the exact cycle date/hour window (e.g. "19 nov 19:00 – 20 nov 18:59").
    public func navigationSubtitle(
        forOffset offset: Int,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = locale
        timeFormatter.dateFormat = "HH:mm"

        let startTime = timeFormatter.string(from: start)
        let endTime = timeFormatter.string(from: displayEnd)

        if offset == 0 || offset == -1 {
            let dayFormatter = DateFormatter()
            dayFormatter.calendar = calendar
            dayFormatter.timeZone = calendar.timeZone
            dayFormatter.locale = locale
            dayFormatter.dateFormat = "d MMM"

            let startDay = dayFormatter.string(from: start)
            let endDay = dayFormatter.string(from: displayEnd)
            if calendar.isDate(start, inSameDayAs: displayEnd) {
                return "\(startDay) · \(startTime) – \(endTime)"
            } else {
                return "\(startDay) \(startTime) – \(endDay) \(endTime)"
            }
        } else {
            return "Ciclo 24h · \(startTime) – \(endTime)"
        }
    }

    /// Full cycle range label showing start and display-end dates and hours (e.g. "19 nov 19:00 – 20 nov 18:59").
    public func formattedRangeLabel(
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        navigationSubtitle(forOffset: 0, calendar: calendar, locale: locale)
    }
}

/// Metadata for a sleep interval (nap or night sleep) that starts in one 24-hour cycle and ends or continues in another.
public struct CrossCycleIntervalInfo: Equatable, Sendable {
    public let interval: SleepInterval
    public let startCycle: SleepCycleRange
    public let endCycle: SleepCycleRange
    public let totalDuration: TimeInterval
    public let isOngoing: Bool

    public init(
        interval: SleepInterval,
        startCycle: SleepCycleRange,
        endCycle: SleepCycleRange,
        totalDuration: TimeInterval,
        isOngoing: Bool
    ) {
        self.interval = interval
        self.startCycle = startCycle
        self.endCycle = endCycle
        self.totalDuration = totalDuration
        self.isOngoing = isOngoing
    }

    public func detailMessage(
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.calendar = calendar
        dateTimeFormatter.timeZone = calendar.timeZone
        dateTimeFormatter.locale = locale
        dateTimeFormatter.dateFormat = "d MMM yyyy, HH:mm"

        let startDateTimeText = dateTimeFormatter.string(from: interval.startTime)
        let totalDurationText = DayMetrics.formatDuration(totalDuration)

        let endLine: String
        if let endTime = interval.endTime {
            let endDateTimeText = dateTimeFormatter.string(from: endTime)
            endLine = "Fin: \(endDateTimeText)"
        } else {
            endLine = "Fin: En curso (el intervalo aún no ha terminado)"
        }

        return """
        Este intervalo de \(interval.classification.displayName.lowercased()) inició en un ciclo de 24h y continúa en otro.

        Inicio: \(startDateTimeText)
        \(endLine)
        Tiempo total actual: \(totalDurationText)

        Si esto es un error, revisa los eventos de "Se durmió" y "Se despertó" correspondientes a este intervalo.
        """
    }
}

public extension SleepInterval {
    /// Formats only the interval's start/end range (without repeating total duration).
    /// Includes dates when `includeDate` is `true` (e.g. for intervals spanning across 24h cycles).
    func rangeText(
        includeDate: Bool,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = includeDate ? "d MMM HH:mm" : "HH:mm"

        let startStr = formatter.string(from: startTime)
        if let end = endTime {
            let endStr = formatter.string(from: end)
            return "\(startStr) - \(endStr)"
        } else {
            return "\(startStr) - Ahora"
        }
    }
}
