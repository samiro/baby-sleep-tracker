import Foundation

public struct DayMetrics: Equatable, Sendable {
    public let date: Date
    public let morningWakeTime: Date?
    public let sleepIntervals: [SleepInterval]
    public let awakeIntervals: [AwakeInterval]
    public let completedNapsCount: Int
    public let totalDaytimeSleepDuration: TimeInterval
    public let totalNightSleepDuration: TimeInterval
    public let totalSleepDuration: TimeInterval
    public let bedtimeRoutineStart: Date?
    public let nightSleepOnset: Date?
    public let routineToSleepDuration: TimeInterval?

    public init(
        date: Date,
        morningWakeTime: Date?,
        sleepIntervals: [SleepInterval],
        awakeIntervals: [AwakeInterval],
        completedNapsCount: Int,
        totalDaytimeSleepDuration: TimeInterval,
        totalNightSleepDuration: TimeInterval,
        totalSleepDuration: TimeInterval,
        bedtimeRoutineStart: Date?,
        nightSleepOnset: Date?,
        routineToSleepDuration: TimeInterval?
    ) {
        self.date = date
        self.morningWakeTime = morningWakeTime
        self.sleepIntervals = sleepIntervals
        self.awakeIntervals = awakeIntervals
        self.completedNapsCount = completedNapsCount
        self.totalDaytimeSleepDuration = totalDaytimeSleepDuration
        self.totalNightSleepDuration = totalNightSleepDuration
        self.totalSleepDuration = totalSleepDuration
        self.bedtimeRoutineStart = bedtimeRoutineStart
        self.nightSleepOnset = nightSleepOnset
        self.routineToSleepDuration = routineToSleepDuration
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
}
