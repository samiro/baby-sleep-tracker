import Foundation

/// Presets and custom selection for the Metrics & Analytics date/cycle horizon.
public enum AnalyticsDateRangePreset: String, CaseIterable, Identifiable, Equatable, Sendable {
    case last7Days
    case last15Days
    case last30Days
    case custom

    public var id: String { rawValue }

    /// Short label suitable for segmented/pill controls.
    public var shortTitle: String {
        switch self {
        case .last7Days: return "7 días"
        case .last15Days: return "15 días"
        case .last30Days: return "30 días"
        case .custom: return "Personalizado"
        }
    }

    /// Descriptive label matching business terminology.
    public var displayTitle: String {
        switch self {
        case .last7Days: return "Última semana"
        case .last15Days: return "Últimos 15 días"
        case .last30Days: return "Último mes"
        case .custom: return "Rango personalizado"
        }
    }

    /// Number of 24h cycles for built-in presets; `nil` for custom ranges.
    public var presetCycleCount: Int? {
        switch self {
        case .last7Days: return 7
        case .last15Days: return 15
        case .last30Days: return 30
        case .custom: return nil
        }
    }
}

/// Aggregated wall-clock time-of-day metric with variability (standard deviation and min–max range).
public struct TimeOfDayAverage: Equatable, Sendable {
    /// Average wall-clock hour (0...23).
    public let averageHour: Int
    /// Average wall-clock minute (0...59).
    public let averageMinute: Int
    /// Standard deviation in seconds across samples (0 when only 1 sample exists).
    public let standardDeviationSeconds: TimeInterval
    /// Earliest sample wall-clock hour (0...23) along the cycle axis.
    public let minHour: Int
    /// Earliest sample wall-clock minute (0...59).
    public let minMinute: Int
    /// Latest sample wall-clock hour (0...23) along the cycle axis.
    public let maxHour: Int
    /// Latest sample wall-clock minute (0...59).
    public let maxMinute: Int
    /// Number of cycle observations included in this average.
    public let sampleCount: Int

    public init(
        averageHour: Int,
        averageMinute: Int,
        standardDeviationSeconds: TimeInterval,
        minHour: Int,
        minMinute: Int,
        maxHour: Int,
        maxMinute: Int,
        sampleCount: Int
    ) {
        self.averageHour = averageHour
        self.averageMinute = averageMinute
        self.standardDeviationSeconds = max(0, standardDeviationSeconds)
        self.minHour = minHour
        self.minMinute = minMinute
        self.maxHour = maxHour
        self.maxMinute = maxMinute
        self.sampleCount = sampleCount
    }

    /// Formatted average time (`HH:mm`).
    public var formattedAverageTime: String {
        SleepScheduleConfiguration.formatTime(hour: averageHour, minute: averageMinute)
    }

    /// Standard deviation rounded to whole minutes.
    public var variationMinutes: Int {
        Int(round(standardDeviationSeconds / 60.0))
    }

    /// Formatted variability badge, e.g. `"± 25 min"` or `"Sin variación"`.
    public var formattedVariation: String {
        guard sampleCount > 1 else {
            return "1 registro"
        }
        let mins = variationMinutes
        if mins == 0 {
            return "± 0 min"
        } else if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0 ? "± \(h)h" : "± \(h)h \(m)m"
        } else {
            return "± \(mins) min"
        }
    }

    /// Formatted earliest–latest time range, e.g. `"19:05 – 19:55"`.
    public var formattedMinMaxRange: String {
        let minStr = SleepScheduleConfiguration.formatTime(hour: minHour, minute: minMinute)
        let maxStr = SleepScheduleConfiguration.formatTime(hour: maxHour, minute: maxMinute)
        return "\(minStr) – \(maxStr)"
    }
}

/// Record for the longest continuous sleep stretch (either nocturnal or daytime nap).
public struct SleepDurationRecord: Equatable, Sendable {
    public let duration: TimeInterval
    public let startTime: Date
    public let endTime: Date
    public let cycleStart: Date

    public init(duration: TimeInterval, startTime: Date, endTime: Date, cycleStart: Date) {
        self.duration = duration
        self.startTime = startTime
        self.endTime = endTime
        self.cycleStart = cycleStart
    }

    public var formattedDuration: String {
        DayMetrics.formatDuration(duration)
    }

    public func formattedDateLabel(
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "d MMM"
        return formatter.string(from: startTime)
    }
}

/// Metrics computed for a single 24-hour sleep cycle within the analytics horizon.
public struct AnalyticsCycleSummary: Identifiable, Equatable, Sendable {
    public var id: Date { cycle.start }
    public let cycle: SleepCycleRange
    public let totalSleepDuration: TimeInterval
    public let nightSleepDuration: TimeInterval
    public let daytimeSleepDuration: TimeInterval
    public let napsCount: Int
    public let nightSleepBlocksCount: Int
    public let nightWakingsCount: Int
    public let nightSleepOnset: Date?
    public let morningWakeTime: Date?
    /// Indicates whether at least one valid completed sleep block contributed to this cycle.
    public let hasCompletedSleepData: Bool

    public init(
        cycle: SleepCycleRange,
        totalSleepDuration: TimeInterval,
        nightSleepDuration: TimeInterval,
        daytimeSleepDuration: TimeInterval,
        napsCount: Int,
        nightSleepBlocksCount: Int,
        nightWakingsCount: Int,
        nightSleepOnset: Date?,
        morningWakeTime: Date?,
        hasCompletedSleepData: Bool
    ) {
        self.cycle = cycle
        self.totalSleepDuration = totalSleepDuration
        self.nightSleepDuration = nightSleepDuration
        self.daytimeSleepDuration = daytimeSleepDuration
        self.napsCount = napsCount
        self.nightSleepBlocksCount = nightSleepBlocksCount
        self.nightWakingsCount = nightWakingsCount
        self.nightSleepOnset = nightSleepOnset
        self.morningWakeTime = morningWakeTime
        self.hasCompletedSleepData = hasCompletedSleepData
    }

    public var nightSleepHours: Double {
        nightSleepDuration / 3600.0
    }

    public var daytimeSleepHours: Double {
        daytimeSleepDuration / 3600.0
    }

    public var totalSleepHours: Double {
        totalSleepDuration / 3600.0
    }

    /// Short date label representing the cycle start day (e.g. "19 nov").
    public func shortDateLabel(
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "d MMM"
        return formatter.string(from: cycle.start)
    }

    /// Compact axis label for charts (e.g. "19").
    public func compactAxisLabel(
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "d/M"
        return formatter.string(from: cycle.start)
    }
}

/// Complete aggregated Metrics & Analytics report for a selected horizon of 24-hour cycles.
public struct SleepAnalyticsReport: Equatable, Sendable {
    public let configuration: SleepScheduleConfiguration
    public let preset: AnalyticsDateRangePreset
    public let cycles: [AnalyticsCycleSummary]

    /// Number of cycles in the selected range that contain at least one valid completed sleep block.
    public let activeCyclesCount: Int
    /// Number of cycles in the selected range with no completed sleep blocks (excluded from average denominators).
    public let emptyCyclesCount: Int
    /// Number of incomplete/orphaned events falling in the selected range that were excluded from calculations.
    public let excludedIncompleteEventsCount: Int

    // 1. Duration Averages & Records
    public let averageTotalSleepDuration: TimeInterval?
    public let averageNightSleepDuration: TimeInterval?
    public let averageDaytimeSleepDuration: TimeInterval?
    public let averageNapDuration: TimeInterval?
    public let totalNapsEvaluated: Int
    public let longestNightStretch: SleepDurationRecord?
    public let longestNap: SleepDurationRecord?

    // 2. Schedule Trend & Consistency
    public let averageNightSleepOnset: TimeOfDayAverage?
    public let averageMorningWakeTime: TimeOfDayAverage?
    public let averageDaytimeWakeWindow: TimeInterval?
    public let daytimeWakeWindowsCount: Int

    // 3. Frequency Averages
    public let averageNapsPerDay: Double?
    public let averageNightWakingsPerCycle: Double?

    public init(
        configuration: SleepScheduleConfiguration,
        preset: AnalyticsDateRangePreset,
        cycles: [AnalyticsCycleSummary],
        activeCyclesCount: Int,
        emptyCyclesCount: Int,
        excludedIncompleteEventsCount: Int,
        averageTotalSleepDuration: TimeInterval?,
        averageNightSleepDuration: TimeInterval?,
        averageDaytimeSleepDuration: TimeInterval?,
        averageNapDuration: TimeInterval?,
        totalNapsEvaluated: Int,
        longestNightStretch: SleepDurationRecord?,
        longestNap: SleepDurationRecord?,
        averageNightSleepOnset: TimeOfDayAverage?,
        averageMorningWakeTime: TimeOfDayAverage?,
        averageDaytimeWakeWindow: TimeInterval?,
        daytimeWakeWindowsCount: Int,
        averageNapsPerDay: Double?,
        averageNightWakingsPerCycle: Double?
    ) {
        self.configuration = configuration
        self.preset = preset
        self.cycles = cycles
        self.activeCyclesCount = activeCyclesCount
        self.emptyCyclesCount = emptyCyclesCount
        self.excludedIncompleteEventsCount = excludedIncompleteEventsCount
        self.averageTotalSleepDuration = averageTotalSleepDuration
        self.averageNightSleepDuration = averageNightSleepDuration
        self.averageDaytimeSleepDuration = averageDaytimeSleepDuration
        self.averageNapDuration = averageNapDuration
        self.totalNapsEvaluated = totalNapsEvaluated
        self.longestNightStretch = longestNightStretch
        self.longestNap = longestNap
        self.averageNightSleepOnset = averageNightSleepOnset
        self.averageMorningWakeTime = averageMorningWakeTime
        self.averageDaytimeWakeWindow = averageDaytimeWakeWindow
        self.daytimeWakeWindowsCount = daytimeWakeWindowsCount
        self.averageNapsPerDay = averageNapsPerDay
        self.averageNightWakingsPerCycle = averageNightWakingsPerCycle
    }

    /// True when no cycle in the selected range has valid completed sleep blocks.
    public var isEmpty: Bool {
        activeCyclesCount == 0
    }

    public var totalCyclesCount: Int {
        cycles.count
    }

    public var rangeStart: Date? {
        cycles.first?.cycle.start
    }

    public var rangeEnd: Date? {
        cycles.last?.cycle.end
    }

    /// Exact cycle boundary summary for the selected period (e.g. "16 nov 19:00 – 23 nov 18:59").
    public func formattedCycleRangeHeader(
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "es_ES")
    ) -> String {
        guard let first = cycles.first?.cycle, let last = cycles.last?.cycle else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "d MMM HH:mm"

        return "\(formatter.string(from: first.start)) – \(formatter.string(from: last.displayEnd))"
    }

    /// Formats a decimal frequency average (e.g. `2.0` -> `"2"`, `2.45` -> `"2.5"`).
    public static func formatFrequency(_ value: Double?) -> String {
        guard let value = value else { return "--" }
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.truncatingRemainder(dividingBy: 1)) < 0.001 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }
}
