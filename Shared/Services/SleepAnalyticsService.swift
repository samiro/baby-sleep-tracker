import Foundation

/// Standalone analytics calculation engine for the Metrics & Analytics module.
/// Processes only valid complete `[Se durmió] -> [Se despertó]` blocks, respects the
/// configured 24-hour cycle boundaries from Settings, and excludes empty cycles from average denominators.
public final class SleepAnalyticsService: @unchecked Sendable {
    public static let shared = SleepAnalyticsService()

    private let trackingService: SleepTrackingService
    private let configurationManager: SleepConfigurationManager

    public init(
        trackingService: SleepTrackingService = .shared,
        configurationManager: SleepConfigurationManager = .shared
    ) {
        self.trackingService = trackingService
        self.configurationManager = configurationManager
    }

    // MARK: - Cycle Horizon Resolution

    /// Returns the 24-hour cycle anchored on the calendar day of `dayDate` at `nightStartHour:nightStartMinute`.
    public func cycleForStartDay(
        _ dayDate: Date,
        configuration: SleepScheduleConfiguration,
        calendar: Calendar = .current
    ) -> SleepCycleRange {
        var components = calendar.dateComponents([.year, .month, .day], from: dayDate)
        components.hour = configuration.nightStartHour
        components.minute = configuration.nightStartMinute
        components.second = 0
        components.nanosecond = 0
        let anchorDate = calendar.date(from: components) ?? dayDate
        return configuration.cycleRange(containing: anchorDate, calendar: calendar)
    }

    /// Resolves the ordered list of 24-hour cycles for a preset or custom date range.
    public func resolveCycles(
        preset: AnalyticsDateRangePreset,
        customStartDate: Date? = nil,
        customEndDate: Date? = nil,
        configuration: SleepScheduleConfiguration? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [SleepCycleRange] {
        let activeConfig = configuration ?? configurationManager.configuration

        if let count = preset.presetCycleCount {
            let safeCount = max(1, count)
            return (-(safeCount - 1)...0).map { offset in
                activeConfig.cycleRange(offset: offset, from: referenceDate, calendar: calendar)
            }
        }

        // Custom range: resolve by cycle start day and clamp end to the current cycle.
        let currentCycle = activeConfig.cycleRange(containing: referenceDate, calendar: calendar)
        let currentStartDay = calendar.startOfDay(for: currentCycle.start)

        let rawStart = customStartDate ?? activeConfig.cycleRange(offset: -6, from: referenceDate, calendar: calendar).start
        let rawEnd = customEndDate ?? currentCycle.start

        let startDayCandidate = min(calendar.startOfDay(for: rawStart), currentStartDay)
        let endDayCandidate = min(calendar.startOfDay(for: rawEnd), currentStartDay)

        let orderedStartDay = min(startDayCandidate, endDayCandidate)
        let orderedEndDay = max(startDayCandidate, endDayCandidate)

        var result: [SleepCycleRange] = []
        var cursor = orderedStartDay
        var guardIterations = 0
        let maxCycles = 366

        while cursor <= orderedEndDay && guardIterations < maxCycles {
            result.append(cycleForStartDay(cursor, configuration: activeConfig, calendar: calendar))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = nextDay
            guardIterations += 1
        }

        return result.isEmpty ? [currentCycle] : result
    }

    // MARK: - Report Generation

    /// Fetches all events from storage and computes the analytics report for the chosen horizon.
    public func generateReport(
        preset: AnalyticsDateRangePreset,
        customStartDate: Date? = nil,
        customEndDate: Date? = nil,
        configuration: SleepScheduleConfiguration? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SleepAnalyticsReport {
        let activeConfig = configuration ?? configurationManager.configuration
        let allEvents = try trackingService.fetchAllEvents(ascending: true)
        return computeReport(
            from: allEvents,
            preset: preset,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            configuration: activeConfig,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    /// Pure calculation entry point (ideal for deterministic unit testing).
    public func computeReport(
        from allEvents: [SleepEvent],
        preset: AnalyticsDateRangePreset,
        customStartDate: Date? = nil,
        customEndDate: Date? = nil,
        configuration: SleepScheduleConfiguration,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> SleepAnalyticsReport {
        let cycles = resolveCycles(
            preset: preset,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            configuration: configuration,
            referenceDate: referenceDate,
            calendar: calendar
        )

        guard let firstCycle = cycles.first, let lastCycle = cycles.last else {
            return SleepAnalyticsReport(
                configuration: configuration,
                preset: preset,
                cycles: [],
                activeCyclesCount: 0,
                emptyCyclesCount: 0,
                excludedIncompleteEventsCount: 0,
                averageTotalSleepDuration: nil,
                averageNightSleepDuration: nil,
                averageDaytimeSleepDuration: nil,
                averageNapDuration: nil,
                totalNapsEvaluated: 0,
                longestNightStretch: nil,
                longestNap: nil,
                averageNightSleepOnset: nil,
                averageMorningWakeTime: nil,
                averageDaytimeWakeWindow: nil,
                daytimeWakeWindowsCount: 0,
                averageNapsPerDay: nil,
                averageNightWakingsPerCycle: nil
            )
        }

        // Analyze full timeline so cross-cycle pairing and incomplete detection are globally consistent.
        // `analysis.sleepIntervals` contains ONLY complete valid [Se durmió] -> [Se despertó] pairs.
        let analysis = trackingService.analyzeTimeline(
            from: allEvents,
            configuration: configuration,
            calendar: calendar
        )
        let completedSleeps = analysis.sleepIntervals
            .filter { $0.isCompleted && $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        let fullRangeStart = firstCycle.start
        let fullRangeEnd = lastCycle.end

        // Count incomplete/orphaned events that occurred inside the selected range for transparency.
        let excludedIncompleteCount = allEvents.filter { event in
            event.timestamp >= fullRangeStart
                && event.timestamp < fullRangeEnd
                && analysis.incompleteEventReasons[event.id] != nil
        }.count

        // Build per-cycle summaries and accumulate range-level records.
        var cycleSummaries: [AnalyticsCycleSummary] = []
        cycleSummaries.reserveCapacity(cycles.count)

        var allRangeNaps: [SleepInterval] = []
        var longestNightRecord: SleepDurationRecord? = nil
        var longestNapRecord: SleepDurationRecord? = nil
        var nightOnsetDates: [Date] = []
        var morningWakeDates: [Date] = []
        var daytimeWakeWindowDurations: [TimeInterval] = []

        for cycle in cycles {
            // Intervals intersecting [cycle.start, cycle.end) contribute their clipped duration to this cycle.
            let intersectingSleeps = completedSleeps.filter { interval in
                guard let endTime = interval.endTime else { return false }
                return interval.startTime < cycle.end && endTime > cycle.start
            }

            // Intervals starting inside [cycle.start, cycle.end) belong to this cycle for counts & records (no double counting).
            let startingSleeps = completedSleeps.filter { interval in
                cycle.contains(interval.startTime)
            }

            var totalSleep: TimeInterval = 0
            var nightSleep: TimeInterval = 0
            var daytimeSleep: TimeInterval = 0

            for interval in intersectingSleeps {
                guard let endTime = interval.endTime else { continue }
                let clippedStart = max(cycle.start, interval.startTime)
                let clippedEnd = min(cycle.end, endTime)
                let effectiveDuration = max(0, clippedEnd.timeIntervalSince(clippedStart))

                totalSleep += effectiveDuration
                if interval.classification == .nap {
                    daytimeSleep += effectiveDuration
                } else {
                    nightSleep += effectiveDuration
                }
            }

            let cycleNaps = startingSleeps.filter { $0.classification == .nap }
            let cycleNightBlocks = startingSleeps.filter { $0.classification == .nightSleep }

            // Night wakings: interruptions between consecutive completed night stretches within the cycle's night window.
            let nightWakings = max(0, cycleNightBlocks.count - 1)

            // Night sleep onset: first completed night sleep block starting inside this cycle's night window.
            let nightOnset = cycleNightBlocks.first { interval in
                configuration.isNightTime(for: interval.startTime, calendar: calendar)
            }?.startTime

            // Morning wake time: first wake from a completed sleep block occurring strictly within this cycle's daytime window.
            let morningWake = intersectingSleeps
                .compactMap { $0.endTime }
                .filter { wakeTime in
                    wakeTime >= cycle.dayStart
                        && wakeTime < cycle.end
                        && configuration.isDayTime(for: wakeTime, calendar: calendar)
                }
                .sorted()
                .first

            let hasData = totalSleep > 0 || !startingSleeps.isEmpty

            if hasData {
                allRangeNaps.append(contentsOf: cycleNaps)

                for nightBlock in cycleNightBlocks {
                    guard let endTime = nightBlock.endTime else { continue }
                    let duration = nightBlock.duration
                    if let currentMax = longestNightRecord {
                        if duration > currentMax.duration {
                            longestNightRecord = SleepDurationRecord(
                                duration: duration,
                                startTime: nightBlock.startTime,
                                endTime: endTime,
                                cycleStart: cycle.start
                            )
                        }
                    } else {
                        longestNightRecord = SleepDurationRecord(
                            duration: duration,
                            startTime: nightBlock.startTime,
                            endTime: endTime,
                            cycleStart: cycle.start
                        )
                    }
                }

                for napBlock in cycleNaps {
                    guard let endTime = napBlock.endTime else { continue }
                    let duration = napBlock.duration
                    if let currentMax = longestNapRecord {
                        if duration > currentMax.duration {
                            longestNapRecord = SleepDurationRecord(
                                duration: duration,
                                startTime: napBlock.startTime,
                                endTime: endTime,
                                cycleStart: cycle.start
                            )
                        }
                    } else {
                        longestNapRecord = SleepDurationRecord(
                            duration: duration,
                            startTime: napBlock.startTime,
                            endTime: endTime,
                            cycleStart: cycle.start
                        )
                    }
                }

                if let onset = nightOnset {
                    nightOnsetDates.append(onset)
                }
                if let wake = morningWake {
                    morningWakeDates.append(wake)
                }
            }

            cycleSummaries.append(
                AnalyticsCycleSummary(
                    cycle: cycle,
                    totalSleepDuration: totalSleep,
                    nightSleepDuration: nightSleep,
                    daytimeSleepDuration: daytimeSleep,
                    napsCount: cycleNaps.count,
                    nightSleepBlocksCount: cycleNightBlocks.count,
                    nightWakingsCount: nightWakings,
                    nightSleepOnset: nightOnset,
                    morningWakeTime: morningWake,
                    hasCompletedSleepData: hasData
                )
            )
        }

        // Compute daytime wake windows between consecutive completed sleep blocks.
        // A wake window belongs to a cycle's daytime if:
        //  (a) It starts during the cycle's daytime window [cycle.dayStart, cycle.end) and ends before the next cycle's dayStart
        //      (covering wake windows between naps and the final wake window before bedtime), OR
        //  (b) It starts during the cycle's night window [cycle.start, cycle.dayStart) and ends during the cycle's daytime window
        //      (covering early-morning wake before the first nap).
        // Gaps spanning across empty/unlogged days are naturally excluded because endTime >= nextCycle.dayStart.
        if completedSleeps.count >= 2 {
            // Precompute next cycle dayStart for each cycle in range.
            let cycleWindows: [(cycle: SleepCycleRange, nextDayStart: Date)] = cycles.map { cycle in
                let nextCycle = configuration.cycleRange(offset: 1, from: cycle.start, calendar: calendar)
                return (cycle, nextCycle.dayStart)
            }

            for index in 0..<(completedSleeps.count - 1) {
                guard let wakeStart = completedSleeps[index].endTime else { continue }
                let wakeEnd = completedSleeps[index + 1].startTime
                let duration = wakeEnd.timeIntervalSince(wakeStart)
                guard duration > 0 else { continue }

                // Check if this wake window belongs to any cycle's daytime in the selected range.
                let matchesDaytimeWindow = cycleWindows.contains { entry in
                    let cycle = entry.cycle
                    let startsInDaytime = wakeStart >= cycle.dayStart
                        && wakeStart < cycle.end
                        && configuration.isDayTime(for: wakeStart, calendar: calendar)
                    if startsInDaytime {
                        return wakeEnd < entry.nextDayStart
                    }

                    let startsInNightAndEndsInDaytime = wakeStart >= cycle.start
                        && wakeStart < cycle.dayStart
                        && wakeEnd >= cycle.dayStart
                        && wakeEnd < cycle.end
                        && configuration.isDayTime(for: wakeEnd, calendar: calendar)
                    return startsInNightAndEndsInDaytime
                }

                if matchesDaytimeWindow {
                    daytimeWakeWindowDurations.append(duration)
                }
            }
        }

        // Exclude cycles with no completed sleep blocks from average denominators.
        let activeCycles = cycleSummaries.filter { $0.hasCompletedSleepData }
        let activeCount = activeCycles.count
        let emptyCount = cycleSummaries.count - activeCount

        let averageTotalSleep: TimeInterval?
        let averageNightSleep: TimeInterval?
        let averageDaytimeSleep: TimeInterval?
        let averageNapsPerDay: Double?
        let averageNightWakings: Double?

        if activeCount > 0 {
            let denominator = Double(activeCount)
            averageTotalSleep = activeCycles.reduce(0) { $0 + $1.totalSleepDuration } / denominator
            averageNightSleep = activeCycles.reduce(0) { $0 + $1.nightSleepDuration } / denominator
            averageDaytimeSleep = activeCycles.reduce(0) { $0 + $1.daytimeSleepDuration } / denominator
            averageNapsPerDay = Double(activeCycles.reduce(0) { $0 + $1.napsCount }) / denominator
            averageNightWakings = Double(activeCycles.reduce(0) { $0 + $1.nightWakingsCount }) / denominator
        } else {
            averageTotalSleep = nil
            averageNightSleep = nil
            averageDaytimeSleep = nil
            averageNapsPerDay = nil
            averageNightWakings = nil
        }

        let averageNapDuration: TimeInterval? = allRangeNaps.isEmpty
            ? nil
            : allRangeNaps.reduce(0) { $0 + $1.duration } / Double(allRangeNaps.count)

        let averageWakeWindow: TimeInterval? = daytimeWakeWindowDurations.isEmpty
            ? nil
            : daytimeWakeWindowDurations.reduce(0, +) / Double(daytimeWakeWindowDurations.count)

        let averageNightOnset = computeTimeOfDayAverage(
            dates: nightOnsetDates,
            anchorHour: configuration.nightStartHour,
            anchorMinute: configuration.nightStartMinute,
            calendar: calendar
        )

        let averageMorningWake = computeTimeOfDayAverage(
            dates: morningWakeDates,
            anchorHour: configuration.dayStartHour,
            anchorMinute: configuration.dayStartMinute,
            calendar: calendar
        )

        return SleepAnalyticsReport(
            configuration: configuration,
            preset: preset,
            cycles: cycleSummaries,
            activeCyclesCount: activeCount,
            emptyCyclesCount: emptyCount,
            excludedIncompleteEventsCount: excludedIncompleteCount,
            averageTotalSleepDuration: averageTotalSleep,
            averageNightSleepDuration: averageNightSleep,
            averageDaytimeSleepDuration: averageDaytimeSleep,
            averageNapDuration: averageNapDuration,
            totalNapsEvaluated: allRangeNaps.count,
            longestNightStretch: longestNightRecord,
            longestNap: longestNapRecord,
            averageNightSleepOnset: averageNightOnset,
            averageMorningWakeTime: averageMorningWake,
            averageDaytimeWakeWindow: averageWakeWindow,
            daytimeWakeWindowsCount: daytimeWakeWindowDurations.count,
            averageNapsPerDay: averageNapsPerDay,
            averageNightWakingsPerCycle: averageNightWakings
        )
    }

    // MARK: - Circular Wall-Clock Averaging

    /// Computes average wall-clock time-of-day, population standard deviation, and min–max bounds
    /// anchored at `anchorHour:anchorMinute` to avoid midnight wrap-around and DST distortion.
    public func computeTimeOfDayAverage(
        dates: [Date],
        anchorHour: Int,
        anchorMinute: Int,
        calendar: Calendar = .current
    ) -> TimeOfDayAverage? {
        guard !dates.isEmpty else { return nil }

        let anchorSeconds = Double(anchorHour * 3600 + anchorMinute * 60)
        let daySeconds = 86_400.0

        let offsets: [Double] = dates.map { date in
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            let second = calendar.component(.second, from: date)
            let clockSeconds = Double(hour * 3600 + minute * 60 + second)
            var delta = clockSeconds - anchorSeconds
            while delta < 0 { delta += daySeconds }
            while delta >= daySeconds { delta -= daySeconds }
            return delta
        }

        let count = Double(offsets.count)
        let meanOffset = offsets.reduce(0, +) / count
        let minOffset = offsets.min() ?? meanOffset
        let maxOffset = offsets.max() ?? meanOffset

        let variance = offsets.reduce(0.0) { partial, value in
            let diff = value - meanOffset
            return partial + diff * diff
        } / count
        let stdDev = sqrt(max(0, variance))

        let avgClock = clockComponents(anchorSeconds: anchorSeconds, offsetSeconds: meanOffset)
        let minClock = clockComponents(anchorSeconds: anchorSeconds, offsetSeconds: minOffset)
        let maxClock = clockComponents(anchorSeconds: anchorSeconds, offsetSeconds: maxOffset)

        return TimeOfDayAverage(
            averageHour: avgClock.hour,
            averageMinute: avgClock.minute,
            standardDeviationSeconds: stdDev,
            minHour: minClock.hour,
            minMinute: minClock.minute,
            maxHour: maxClock.hour,
            maxMinute: maxClock.minute,
            sampleCount: offsets.count
        )
    }

    private func clockComponents(anchorSeconds: Double, offsetSeconds: Double) -> (hour: Int, minute: Int) {
        let totalMinutes = Int(round((anchorSeconds + offsetSeconds) / 60.0)) % 1440
        let normalized = (totalMinutes + 1440) % 1440
        return (hour: normalized / 60, minute: normalized % 60)
    }
}
