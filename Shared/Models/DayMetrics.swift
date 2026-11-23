import Foundation

public struct DayMetrics: Equatable, Sendable {
    public let date: Date
    public let cycleEnd: Date
    public let morningWakeTime: Date?
    public let sleepIntervals: [SleepInterval]
    public let awakeIntervals: [AwakeInterval]
    public let completedNapsCount: Int
    public let totalDaytimeSleepDuration: TimeInterval
    public let totalNightSleepDuration: TimeInterval
    public let totalSleepDuration: TimeInterval
    public let nightSleepOnset: Date?
    public let nightWakingsCount: Int
    public let longestNightSleepDuration: TimeInterval?
    public let longestNightAwakeDuration: TimeInterval?
    public let longestDaytimeSleepDuration: TimeInterval?
    public let longestDaytimeAwakeDuration: TimeInterval?

    public var cycleStart: Date { date }

    public init(
        date: Date,
        cycleEnd: Date? = nil,
        morningWakeTime: Date?,
        sleepIntervals: [SleepInterval],
        awakeIntervals: [AwakeInterval],
        completedNapsCount: Int,
        totalDaytimeSleepDuration: TimeInterval,
        totalNightSleepDuration: TimeInterval,
        totalSleepDuration: TimeInterval,
        nightSleepOnset: Date?,
        nightWakingsCount: Int = 0,
        longestNightSleepDuration: TimeInterval? = nil,
        longestNightAwakeDuration: TimeInterval? = nil,
        longestDaytimeSleepDuration: TimeInterval? = nil,
        longestDaytimeAwakeDuration: TimeInterval? = nil
    ) {
        self.date = date
        self.cycleEnd = cycleEnd ?? date.addingTimeInterval(24 * 3600)
        self.morningWakeTime = morningWakeTime
        self.sleepIntervals = sleepIntervals
        self.awakeIntervals = awakeIntervals
        self.completedNapsCount = completedNapsCount
        self.totalDaytimeSleepDuration = totalDaytimeSleepDuration
        self.totalNightSleepDuration = totalNightSleepDuration
        self.totalSleepDuration = totalSleepDuration
        self.nightSleepOnset = nightSleepOnset
        self.nightWakingsCount = nightWakingsCount
        self.longestNightSleepDuration = longestNightSleepDuration
        self.longestNightAwakeDuration = longestNightAwakeDuration
        self.longestDaytimeSleepDuration = longestDaytimeSleepDuration
        self.longestDaytimeAwakeDuration = longestDaytimeAwakeDuration
    }

    public static func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    public static func formatOptionalDuration(_ duration: TimeInterval?) -> String {
        guard let duration else { return "—" }
        return formatDuration(duration)
    }

    /// Total nighttime sleep duration for this cycle including an active ongoing night sleep (if any),
    /// clipped strictly to `[cycleStart, min(cycleEnd, now)]`.
    public func effectiveTotalNightSleepDuration(
        including ongoingInterval: SleepInterval?,
        at now: Date = Date()
    ) -> TimeInterval {
        totalNightSleepDuration + ongoingDurationClippedToCycle(ongoingInterval, matching: .nightSleep, at: now)
    }

    /// Total daytime sleep duration for this cycle including an active ongoing nap (if any),
    /// clipped strictly to `[cycleStart, min(cycleEnd, now)]`.
    public func effectiveTotalDaytimeSleepDuration(
        including ongoingInterval: SleepInterval?,
        at now: Date = Date()
    ) -> TimeInterval {
        totalDaytimeSleepDuration + ongoingDurationClippedToCycle(ongoingInterval, matching: .nap, at: now)
    }

    private func ongoingDurationClippedToCycle(
        _ ongoingInterval: SleepInterval?,
        matching classification: SleepClassification,
        at now: Date
    ) -> TimeInterval {
        guard let ongoing = ongoingInterval,
              !ongoing.isCompleted,
              ongoing.classification == classification,
              now >= cycleStart,
              now < cycleEnd else {
            return 0
        }
        let clippedStart = max(cycleStart, ongoing.startTime)
        let clippedEnd = min(cycleEnd, now)
        return max(0, clippedEnd.timeIntervalSince(clippedStart))
    }
}
