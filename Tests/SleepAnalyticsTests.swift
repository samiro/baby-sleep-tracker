import XCTest

final class SleepAnalyticsTests: XCTestCase {
    var tempDirectory: URL!
    var database: SQLiteDatabase!
    var userDefaults: UserDefaults!
    var configManager: SleepConfigurationManager!
    var trackingService: SleepTrackingService!
    var analyticsService: SleepAnalyticsService!
    var calendar: Calendar!

    override func setUpWithError() throws {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let dbURL = tempDirectory.appendingPathComponent("analytics_test.sqlite3")
        database = try SQLiteDatabase(url: dbURL)

        let suiteName = "analytics_test_suite_\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        configManager = SleepConfigurationManager(userDefaults: userDefaults)
        trackingService = SleepTrackingService(database: database, configurationManager: configManager)
        analyticsService = SleepAnalyticsService(trackingService: trackingService, configurationManager: configManager)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        calendar = cal
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        userDefaults.removePersistentDomain(forName: userDefaults.description)
        analyticsService = nil
        trackingService = nil
        configManager = nil
        database = nil
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeDate(year: Int = 2026, month: Int = 11, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }

    private func makeBlock(
        startDay: Int, startHour: Int, startMinute: Int = 0,
        endDay: Int, endHour: Int, endMinute: Int = 0
    ) -> [SleepEvent] {
        let s = SleepEvent(type: .sleep, timestamp: makeDate(day: startDay, hour: startHour, minute: startMinute))
        let w = SleepEvent(type: .wake, timestamp: makeDate(day: endDay, hour: endHour, minute: endMinute))
        return [s, w]
    }

    // MARK: - 1. Date / Cycle Range Resolution Tests

    func testPresetCycleResolutionRespectsCustom24HourCycle() {
        let config = SleepScheduleConfiguration(
            nightStartHour: 19,
            nightStartMinute: 30,
            dayStartHour: 7,
            dayStartMinute: 0
        )
        // Reference: Nov 22 at 14:00 -> current cycle started Nov 21 at 19:30 and ends Nov 22 at 19:30
        let ref = makeDate(day: 22, hour: 14, minute: 0)

        let weekCycles = analyticsService.resolveCycles(preset: .last7Days, configuration: config, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(weekCycles.count, 7)
        XCTAssertEqual(weekCycles.first?.start, makeDate(day: 15, hour: 19, minute: 30))
        XCTAssertEqual(weekCycles.last?.start, makeDate(day: 21, hour: 19, minute: 30))
        XCTAssertEqual(weekCycles.last?.end, makeDate(day: 22, hour: 19, minute: 30))

        let fifteenCycles = analyticsService.resolveCycles(preset: .last15Days, configuration: config, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(fifteenCycles.count, 15)
        XCTAssertEqual(fifteenCycles.first?.start, makeDate(day: 7, hour: 19, minute: 30))

        let monthCycles = analyticsService.resolveCycles(preset: .last30Days, configuration: config, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(monthCycles.count, 30)
    }

    func testCustomRangeResolutionSwapsReversedDatesAndClampsFuture() {
        let config = SleepScheduleConfiguration.standard // 19:00 - 07:00
        let ref = makeDate(day: 22, hour: 21, minute: 0) // current cycle starts Nov 22 19:00

        // Reversed dates (end before start)
        let reversed = analyticsService.resolveCycles(
            preset: .custom,
            customStartDate: makeDate(day: 20, hour: 12),
            customEndDate: makeDate(day: 18, hour: 12),
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertEqual(reversed.count, 3)
        XCTAssertEqual(reversed.first?.start, makeDate(day: 18, hour: 19, minute: 0))
        XCTAssertEqual(reversed.last?.start, makeDate(day: 20, hour: 19, minute: 0))

        // Future end date gets clamped to current cycle
        let clamped = analyticsService.resolveCycles(
            preset: .custom,
            customStartDate: makeDate(day: 21, hour: 10),
            customEndDate: makeDate(day: 28, hour: 10),
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertEqual(clamped.count, 2)
        XCTAssertEqual(clamped.last?.start, makeDate(day: 22, hour: 19, minute: 0))
    }

    // MARK: - 2. Empty Cycle Exclusion & Incomplete Event Integrity

    func testEmptyCyclesAreExcludedFromAverageDenominators() {
        let config = SleepScheduleConfiguration.standard // 19:00 - 07:00
        let ref = makeDate(day: 22, hour: 18, minute: 0) // 7 cycles: Nov 15 19:00 ... Nov 21 19:00

        // Only populate 2 out of 7 cycles (Cycle Nov 18 and Cycle Nov 20). The other 5 cycles are empty!
        var events: [SleepEvent] = []
        // Cycle Nov 18 (18 19:00 -> 19 19:00): Night 10h + 2 naps (1h + 2h = 3h) -> Total 13h, 0 night wakings
        events += makeBlock(startDay: 18, startHour: 20, endDay: 19, endHour: 6)
        events += makeBlock(startDay: 19, startHour: 9, endDay: 19, endHour: 10)
        events += makeBlock(startDay: 19, startHour: 13, endDay: 19, endHour: 15)

        // Cycle Nov 20 (20 19:00 -> 21 19:00): Night 2 blocks (4h + 4h = 8h, 1 night waking) + 1 nap (1h) -> Total 9h
        events += makeBlock(startDay: 20, startHour: 20, endDay: 21, endHour: 0)
        events += makeBlock(startDay: 21, startHour: 1, endDay: 21, endHour: 5)
        events += makeBlock(startDay: 21, startHour: 10, endDay: 21, endHour: 11)

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        XCTAssertFalse(report.isEmpty)
        XCTAssertEqual(report.totalCyclesCount, 7)
        XCTAssertEqual(report.activeCyclesCount, 2)
        XCTAssertEqual(report.emptyCyclesCount, 5)

        // Averages MUST divide by 2 (active cycles), NOT 7!
        // Total sleep: (13h + 9h) / 2 = 11h
        XCTAssertEqual(report.averageTotalSleepDuration ?? 0, 11 * 3600, accuracy: 1.0)
        // Night sleep: (10h + 8h) / 2 = 9h
        XCTAssertEqual(report.averageNightSleepDuration ?? 0, 9 * 3600, accuracy: 1.0)
        // Daytime sleep: (3h + 1h) / 2 = 2h
        XCTAssertEqual(report.averageDaytimeSleepDuration ?? 0, 2 * 3600, accuracy: 1.0)
        // Naps per day: (2 + 1) / 2 = 1.5
        XCTAssertEqual(report.averageNapsPerDay ?? 0, 1.5, accuracy: 0.001)
        // Night wakings: (0 + 1) / 2 = 0.5
        XCTAssertEqual(report.averageNightWakingsPerCycle ?? 0, 0.5, accuracy: 0.001)

        // Average nap duration across 3 naps: (1h + 2h + 1h) / 3 = 80 min
        XCTAssertEqual(report.totalNapsEvaluated, 3)
        XCTAssertEqual(report.averageNapDuration ?? 0, 80 * 60, accuracy: 1.0)

        // Records
        XCTAssertEqual(report.longestNightStretch?.duration ?? 0, 10 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.longestNap?.duration ?? 0, 2 * 3600, accuracy: 1.0)
    }

    func testIncompleteAndOrphanedEventsAreExcludedFromAllMetrics() {
        let config = SleepScheduleConfiguration.standard
        let ref = makeDate(day: 22, hour: 18, minute: 0)

        // Cycle Nov 19:
        // - Orphaned sleep at 19:15 (no wake)
        // - Valid night sleep 20:00 -> 07:00 (11h)
        // - Orphaned extra wake at 07:30 (consecutive wake)
        // - Valid nap 10:00 -> 11:30 (1.5h)
        // - Trailing ongoing sleep at 14:00 (no wake yet)
        let events: [SleepEvent] = [
            SleepEvent(type: .sleep, timestamp: makeDate(day: 19, hour: 19, minute: 15)),
            SleepEvent(type: .sleep, timestamp: makeDate(day: 19, hour: 20, minute: 0)),
            SleepEvent(type: .wake, timestamp: makeDate(day: 20, hour: 7, minute: 0)),
            SleepEvent(type: .wake, timestamp: makeDate(day: 20, hour: 7, minute: 30)),
            SleepEvent(type: .sleep, timestamp: makeDate(day: 20, hour: 10, minute: 0)),
            SleepEvent(type: .wake, timestamp: makeDate(day: 20, hour: 11, minute: 30)),
            SleepEvent(type: .sleep, timestamp: makeDate(day: 20, hour: 14, minute: 0))
        ]

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        XCTAssertEqual(report.activeCyclesCount, 1)
        XCTAssertEqual(report.excludedIncompleteEventsCount, 3)
        XCTAssertEqual(report.excludedIncompleteEvents.count, 3)
        // Sorted most recent first: trailing ongoing sleep (14:00), extra wake (07:30), orphaned sleep (19:15)
        XCTAssertEqual(report.ongoingExcludedEvent?.event.id, events[6].id)
        XCTAssertEqual(report.realIncompleteEvents.count, 2)
        XCTAssertEqual(report.realIncompleteEvents[0].event.id, events[3].id)
        XCTAssertEqual(report.realIncompleteEvents[0].reason, .missingPrecedingSleep)
        XCTAssertEqual(report.realIncompleteEvents[1].event.id, events[0].id)
        XCTAssertEqual(report.realIncompleteEvents[1].reason, .missingSubsequentWake(isLatestTimelineEvent: false))
        XCTAssertEqual(report.averageNightSleepDuration ?? 0, 11 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.averageDaytimeSleepDuration ?? 0, 1.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.averageTotalSleepDuration ?? 0, 12.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.averageNapsPerDay ?? 0, 1.0, accuracy: 0.001)
        // Night sleep onset must be 20:00 (valid block), NOT 19:15 (orphaned sleep)!
        XCTAssertEqual(report.averageNightSleepOnset?.averageHour, 20)
        XCTAssertEqual(report.averageNightSleepOnset?.averageMinute, 0)
        // Morning wake must be 07:00 (valid block end), NOT 07:30 (orphaned wake)!
        XCTAssertEqual(report.averageMorningWakeTime?.averageHour, 7)
        XCTAssertEqual(report.averageMorningWakeTime?.averageMinute, 0)
    }

    func testRangeWithOnlyIncompleteEventsReturnsEmptyReport() {
        let config = SleepScheduleConfiguration.standard
        let ref = makeDate(day: 22, hour: 18, minute: 0)

        let events: [SleepEvent] = [
            SleepEvent(type: .sleep, timestamp: makeDate(day: 21, hour: 20, minute: 0))
        ]

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.activeCyclesCount, 0)
        XCTAssertEqual(report.excludedIncompleteEventsCount, 1)
        XCTAssertEqual(report.excludedIncompleteEvents.count, 1)
        XCTAssertEqual(report.excludedIncompleteEvents.first?.event.id, events[0].id)
        XCTAssertNil(report.averageTotalSleepDuration)
        XCTAssertNil(report.longestNightStretch)
        XCTAssertNil(report.averageNightSleepOnset)
    }

    // MARK: - 3. Schedule Averages, Midnight Wrap-Around & Wake Windows

    func testNightOnsetAverageHandlesMidnightWrapAroundAccurately() {
        let config = SleepScheduleConfiguration.standard // Night starts 19:00
        let ref = makeDate(day: 22, hour: 18, minute: 0)

        var events: [SleepEvent] = []
        // Cycle 1 (Nov 18 19:00 - Nov 19 19:00): Bedtime 23:30 -> 07:10
        events += makeBlock(startDay: 18, startHour: 23, startMinute: 30, endDay: 19, endHour: 7, endMinute: 10)
        // Cycle 2 (Nov 19 19:00 - Nov 20 19:00): Bedtime 00:30 (next calendar day, still night of cycle 2!) -> 07:50
        events += makeBlock(startDay: 20, startHour: 0, startMinute: 30, endDay: 20, endHour: 7, endMinute: 50)

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        // Average of 23:30 and 00:30 MUST be 00:00 (± 30 min), NOT 12:00!
        let bedtime = try! XCTUnwrap(report.averageNightSleepOnset)
        XCTAssertEqual(bedtime.averageHour, 0)
        XCTAssertEqual(bedtime.averageMinute, 0)
        XCTAssertEqual(bedtime.variationMinutes, 30)
        XCTAssertEqual(bedtime.formattedMinMaxRange, "23:30 – 00:30")

        // Average of 07:10 and 07:50 MUST be 07:30 (± 20 min)
        let morningWake = try! XCTUnwrap(report.averageMorningWakeTime)
        XCTAssertEqual(morningWake.averageHour, 7)
        XCTAssertEqual(morningWake.averageMinute, 30)
        XCTAssertEqual(morningWake.variationMinutes, 20)
        XCTAssertEqual(morningWake.formattedMinMaxRange, "07:10 – 07:50")
    }

    func testDaytimeWakeWindowsExcludeNightWakingsAndMultiDayUnloggedGaps() {
        let config = SleepScheduleConfiguration.standard // 19:00 - 07:00
        let ref = makeDate(day: 22, hour: 18, minute: 0)

        var events: [SleepEvent] = []
        // Cycle Nov 17 (17 19:00 -> 18 19:00):
        // Night stretch 1: 19:30 -> 02:00
        // Night waking: 02:00 -> 02:30 (30m) -- MUST NOT be a daytime wake window!
        // Night stretch 2: 02:30 -> 07:00
        // Daytime WW 1: 07:00 -> 09:00 (2h)
        // Nap 1: 09:00 -> 10:30
        // Daytime WW 2: 10:30 -> 13:30 (3h)
        // Nap 2: 13:30 -> 15:00
        // Daytime WW 3: 15:00 -> 19:00 (4h) -> next cycle bedtime!
        events += makeBlock(startDay: 17, startHour: 19, startMinute: 30, endDay: 18, endHour: 2, endMinute: 0)
        events += makeBlock(startDay: 18, startHour: 2, startMinute: 30, endDay: 18, endHour: 7, endMinute: 0)
        events += makeBlock(startDay: 18, startHour: 9, startMinute: 0, endDay: 18, endHour: 10, endMinute: 30)
        events += makeBlock(startDay: 18, startHour: 13, startMinute: 30, endDay: 18, endHour: 15, endMinute: 0)

        // Cycle Nov 18 bedtime at 19:00 -> 07:00 (closes WW 3 cleanly)
        events += makeBlock(startDay: 18, startHour: 19, startMinute: 0, endDay: 19, endHour: 7, endMinute: 0)

        // Skip Nov 19 completely (empty gap!), then resume on Nov 21 20:00 -> 07:00
        // The 61-hour gap from Nov 19 07:00 to Nov 21 20:00 MUST NOT pollute wake windows!
        events += makeBlock(startDay: 21, startHour: 20, startMinute: 0, endDay: 22, endHour: 7, endMinute: 0)

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        // Daytime wake windows: 2h, 3h, 4h -> average = 3h (3 windows across 3 active cycles -> 1.0/cycle)
        XCTAssertEqual(report.daytimeWakeWindowsCount, 3)
        XCTAssertEqual(report.averageDaytimeWakeWindow ?? 0, 3 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.averageDaytimeWakingsPerCycle ?? 0, 1.0, accuracy: 0.001)
        // Night wakings: Cycle Nov 17 had 1 (30m), Cycle Nov 18 had 0, Cycle Nov 21 had 0 -> 1 / 3, avg duration = 30m
        XCTAssertEqual(report.averageNightWakingsPerCycle ?? 0, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(report.nightWakeWindowsCount, 1)
        XCTAssertEqual(report.averageNightWakingDuration ?? 0, 30 * 60, accuracy: 1.0)
    }

    func testDaytimeAndNightWakingCountsAndDurationsAcrossActiveCycles() {
        let config = SleepScheduleConfiguration.standard // 19:00 - 07:00
        let ref = makeDate(day: 22, hour: 18, minute: 0)

        var events: [SleepEvent] = []

        // Cycle Nov 18 (active #1):
        // - Night block 1: 19:30 -> 23:00
        // - Night waking 1: 23:00 -> 23:20 (20m)
        // - Night block 2: 23:20 -> 03:00
        // - Night waking 2: 03:00 -> 03:40 (40m)
        // - Night block 3: 03:40 -> 07:00
        // - Daytime wake 1: 07:00 -> 09:30 (2h 30m)
        // - Nap 1: 09:30 -> 11:00
        // - Daytime wake 2: 11:00 -> 14:30 (3h 30m)
        // - Nap 2: 14:30 -> 16:00
        // - Daytime wake 3: 16:00 -> 19:30 (3h 30m) -> closed by Cycle Nov 19 bedtime
        events += makeBlock(startDay: 18, startHour: 19, startMinute: 30, endDay: 18, endHour: 23, endMinute: 0)
        events += makeBlock(startDay: 18, startHour: 23, startMinute: 20, endDay: 19, endHour: 3, endMinute: 0)
        events += makeBlock(startDay: 19, startHour: 3, startMinute: 40, endDay: 19, endHour: 7, endMinute: 0)
        events += makeBlock(startDay: 19, startHour: 9, startMinute: 30, endDay: 19, endHour: 11, endMinute: 0)
        events += makeBlock(startDay: 19, startHour: 14, startMinute: 30, endDay: 19, endHour: 16, endMinute: 0)

        // Cycle Nov 19 (active #2):
        // - Night block 1: 19:30 -> 01:00
        // - Night waking 1: 01:00 -> 02:00 (60m)
        // - Night block 2: 02:00 -> 07:00
        // - Daytime wake 1: 07:00 -> 10:00 (3h)
        // - Nap 1: 10:00 -> 11:30
        events += makeBlock(startDay: 19, startHour: 19, startMinute: 30, endDay: 20, endHour: 1, endMinute: 0)
        events += makeBlock(startDay: 20, startHour: 2, startMinute: 0, endDay: 20, endHour: 7, endMinute: 0)
        events += makeBlock(startDay: 20, startHour: 10, startMinute: 0, endDay: 20, endHour: 11, endMinute: 30)

        // Remaining 5 cycles in the 7-day range are empty and MUST be excluded from denominators.
        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        XCTAssertEqual(report.activeCyclesCount, 2)
        XCTAssertEqual(report.emptyCyclesCount, 5)

        // Daytime wakings: 3 in Nov 18 + 1 in Nov 19 = 4 across 2 active cycles -> 2.0 / day
        // Durations: 150m, 210m, 210m, 180m -> avg = 750 / 4 = 187.5m = 11250s
        XCTAssertEqual(report.daytimeWakeWindowsCount, 4)
        XCTAssertEqual(report.averageDaytimeWakingsPerCycle ?? 0, 2.0, accuracy: 0.001)
        XCTAssertEqual(report.averageDaytimeWakeWindow ?? 0, 11250, accuracy: 1.0)

        // Night wakings: 2 in Nov 18 (20m, 40m) + 1 in Nov 19 (60m) = 3 across 2 active cycles -> 1.5 / night
        // Durations: 20m, 40m, 60m -> avg = 40m = 2400s
        XCTAssertEqual(report.nightWakeWindowsCount, 3)
        XCTAssertEqual(report.averageNightWakingsPerCycle ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(report.averageNightWakingDuration ?? 0, 40 * 60, accuracy: 1.0)

        let cycle18 = report.cycles.first { $0.cycle.start == makeDate(day: 18, hour: 19) }
        let cycle19 = report.cycles.first { $0.cycle.start == makeDate(day: 19, hour: 19) }
        XCTAssertEqual(cycle18?.daytimeWakingsCount, 3)
        XCTAssertEqual(cycle18?.nightWakingsCount, 2)
        XCTAssertEqual(cycle19?.daytimeWakingsCount, 1)
        XCTAssertEqual(cycle19?.nightWakingsCount, 1)
    }

    func testZeroNightWakingsReturnsZeroCountAndNilDuration() {
        let config = SleepScheduleConfiguration.standard // 19:00 - 07:00
        let ref = makeDate(day: 22, hour: 18, minute: 0)

        // Uninterrupted night sleep + 1 nap (no night wakings, 1 daytime wake window)
        var events: [SleepEvent] = []
        events += makeBlock(startDay: 20, startHour: 20, startMinute: 0, endDay: 21, endHour: 7, endMinute: 0)
        events += makeBlock(startDay: 21, startHour: 10, startMinute: 0, endDay: 21, endHour: 11, endMinute: 30)

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        XCTAssertEqual(report.activeCyclesCount, 1)
        XCTAssertEqual(report.averageNightWakingsPerCycle ?? -1, 0.0, accuracy: 0.001)
        XCTAssertEqual(report.nightWakeWindowsCount, 0)
        XCTAssertNil(report.averageNightWakingDuration)
        XCTAssertEqual(report.averageDaytimeWakingsPerCycle ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(report.averageDaytimeWakeWindow ?? 0, 3 * 3600, accuracy: 1.0)
    }

    // MARK: - 4. Dynamic Classification & Cross-Cycle Clipping

    func testDynamicClassificationFollowsConfiguredSchedule() {
        let ref = makeDate(day: 22, hour: 18, minute: 0)
        // A sleep block from 19:30 -> 20:30 (1h)
        // Under 19:00-07:00 it is NIGHT sleep; under 21:00-08:00 it is DAYTIME nap!
        let events = makeBlock(startDay: 20, startHour: 19, startMinute: 30, endDay: 20, endHour: 20, endMinute: 30)

        let earlyConfig = SleepScheduleConfiguration(nightStartHour: 19, nightStartMinute: 0, dayStartHour: 7, dayStartMinute: 0)
        let earlyReport = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: earlyConfig,
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertEqual(earlyReport.averageNightSleepDuration ?? 0, 3600, accuracy: 1.0)
        XCTAssertEqual(earlyReport.averageDaytimeSleepDuration ?? 0, 0, accuracy: 1.0)
        XCTAssertEqual(earlyReport.totalNapsEvaluated, 0)

        let lateConfig = SleepScheduleConfiguration(nightStartHour: 21, nightStartMinute: 0, dayStartHour: 8, dayStartMinute: 0)
        let lateReport = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: lateConfig,
            referenceDate: ref,
            calendar: calendar
        )
        XCTAssertEqual(lateReport.averageNightSleepDuration ?? 0, 0, accuracy: 1.0)
        XCTAssertEqual(lateReport.averageDaytimeSleepDuration ?? 0, 3600, accuracy: 1.0)
        XCTAssertEqual(lateReport.totalNapsEvaluated, 1)
    }

    func testCrossCycleSleepIntervalClipsDurationsWithoutDoubleCountingNaps() {
        let config = SleepScheduleConfiguration.standard // 19:00 - 07:00
        let ref = makeDate(day: 22, hour: 18, minute: 0)

        // Late nap starting at 18:30 (Cycle Nov 19) and ending at 19:30 (Cycle Nov 20)
        let events = makeBlock(startDay: 20, startHour: 18, startMinute: 30, endDay: 20, endHour: 19, endMinute: 30)

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        // Total nap count must be 1 (not double-counted across both cycles)
        XCTAssertEqual(report.totalNapsEvaluated, 1)
        XCTAssertEqual(report.longestNap?.duration ?? 0, 3600, accuracy: 1.0)

        // Cycle Nov 19 (19 19:00 - 20 19:00) gets 30m clipped; Cycle Nov 20 (20 19:00 - 21 19:00) gets 30m clipped
        let cycle19 = report.cycles.first { $0.cycle.start == makeDate(day: 19, hour: 19) }
        let cycle20 = report.cycles.first { $0.cycle.start == makeDate(day: 20, hour: 19) }
        XCTAssertEqual(cycle19?.daytimeSleepDuration ?? 0, 1800, accuracy: 1.0)
        XCTAssertEqual(cycle20?.daytimeSleepDuration ?? 0, 1800, accuracy: 1.0)
    }

    // MARK: - 5. End-to-End Integration with SQLite Storage

    func testGenerateReportFromSQLiteDatabase() throws {
        let config = SleepScheduleConfiguration.standard
        configManager.save(config)

        let ref = makeDate(day: 22, hour: 18, minute: 0)
        try trackingService.recordEvent(type: .sleep, timestamp: makeDate(day: 20, hour: 20, minute: 0), force: true)
        try trackingService.recordEvent(type: .wake, timestamp: makeDate(day: 21, hour: 7, minute: 0), force: true)
        try trackingService.recordEvent(type: .sleep, timestamp: makeDate(day: 21, hour: 10, minute: 0), force: true)
        try trackingService.recordEvent(type: .wake, timestamp: makeDate(day: 21, hour: 11, minute: 30), force: true)

        let report = try analyticsService.generateReport(
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        XCTAssertFalse(report.isEmpty)
        XCTAssertEqual(report.activeCyclesCount, 1)
        XCTAssertEqual(report.averageNightSleepDuration ?? 0, 11 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.averageDaytimeSleepDuration ?? 0, 1.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.averageTotalSleepDuration ?? 0, 12.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(report.daytimeWakeWindowsCount, 1)
        XCTAssertEqual(report.averageDaytimeWakeWindow ?? 0, 3 * 3600, accuracy: 1.0)
    }

    // MARK: - 6. Night Record History Navigation Offset

    func testCycleOffsetMapsNightRecordDateToExactCycleIncludingPostMidnightStart() throws {
        let config = SleepScheduleConfiguration(
            nightStartHour: 19,
            nightStartMinute: 30,
            dayStartHour: 7,
            dayStartMinute: 0
        )
        // Reference: Nov 22 at 15:00 -> current cycle is Nov 21 19:30 – Nov 22 19:30
        let ref = makeDate(day: 22, hour: 15, minute: 0)

        var events: [SleepEvent] = []
        // Cycle Nov 18 (offset -3): 4h night block
        events += makeBlock(startDay: 18, startHour: 20, endDay: 19, endHour: 0)
        // Cycle Nov 19 (offset -2): longest night stretch starting AFTER midnight on Nov 20 00:15 -> 06:45 (6.5h)
        events += makeBlock(startDay: 20, startHour: 0, startMinute: 15, endDay: 20, endHour: 6, endMinute: 45)
        // Cycle Nov 21 (offset 0): 5h night block
        events += makeBlock(startDay: 21, startHour: 21, endDay: 22, endHour: 2)

        let report = analyticsService.computeReport(
            from: events,
            preset: .last7Days,
            configuration: config,
            referenceDate: ref,
            calendar: calendar
        )

        let record = try XCTUnwrap(report.longestNightStretch)
        XCTAssertEqual(record.startTime, makeDate(day: 20, hour: 0, minute: 15))
        XCTAssertEqual(record.cycleStart, makeDate(day: 19, hour: 19, minute: 30))

        // Offset computed from record.startTime must resolve to exact cycle Nov 19 19:30 – Nov 20 19:30 (offset -2)
        let offset = config.cycleOffset(for: record.startTime, relativeTo: ref, calendar: calendar)
        XCTAssertEqual(offset, -2)
        XCTAssertEqual(
            config.cycleRange(offset: offset, from: ref, calendar: calendar).start,
            record.cycleStart
        )

        // Current cycle & future timestamps clamp to 0
        XCTAssertEqual(config.cycleOffset(for: makeDate(day: 21, hour: 21), relativeTo: ref, calendar: calendar), 0)
        XCTAssertEqual(config.cycleOffset(for: makeDate(day: 25, hour: 21), relativeTo: ref, calendar: calendar), 0)
    }
}
