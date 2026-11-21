import XCTest

final class SleepScheduleConfigurationTests: XCTestCase {
    var tempDirectory: URL!
    var database: SQLiteDatabase!
    var service: SleepTrackingService!
    var userDefaults: UserDefaults!
    var configManager: SleepConfigurationManager!

    override func setUpWithError() throws {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let dbURL = tempDirectory.appendingPathComponent("test.sqlite3")
        database = try SQLiteDatabase(url: dbURL)

        let suiteName = "test_suite_\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        configManager = SleepConfigurationManager(userDefaults: userDefaults)
        service = SleepTrackingService(database: database, configurationManager: configManager)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        userDefaults.removePersistentDomain(forName: userDefaults.description)
        userDefaults = nil
        configManager = nil
        database = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Model Unit Tests

    func testStandardScheduleClassification() {
        let config = SleepScheduleConfiguration.standard
        XCTAssertEqual(config.nightStartHour, 19)
        XCTAssertEqual(config.nightStartMinute, 0)
        XCTAssertEqual(config.dayStartHour, 7)
        XCTAssertEqual(config.dayStartMinute, 0)

        // Day time (naps)
        XCTAssertFalse(config.isNightTime(hour: 7, minute: 0))
        XCTAssertTrue(config.isDayTime(for: makeDate(hour: 7, minute: 0)))
        XCTAssertTrue(config.isDayTime(for: makeDate(hour: 12, minute: 30)))
        XCTAssertTrue(config.isDayTime(for: makeDate(hour: 18, minute: 59)))

        // Night time (night sleep)
        XCTAssertTrue(config.isNightTime(hour: 19, minute: 0))
        XCTAssertTrue(config.isNightTime(hour: 23, minute: 59))
        XCTAssertTrue(config.isNightTime(hour: 0, minute: 0))
        XCTAssertTrue(config.isNightTime(hour: 4, minute: 15))
        XCTAssertTrue(config.isNightTime(hour: 6, minute: 59))

        // Classify method
        XCTAssertEqual(config.classify(timestamp: makeDate(hour: 14, minute: 0)), .nap)
        XCTAssertEqual(config.classify(timestamp: makeDate(hour: 20, minute: 0)), .nightSleep)
        XCTAssertEqual(config.classify(timestamp: makeDate(hour: 2, minute: 0)), .nightSleep)
    }

    func testCustomScheduleWithMinutes() {
        // Bedtime 20:30, wake up 07:45
        let config = SleepScheduleConfiguration(
            nightStartHour: 20,
            nightStartMinute: 30,
            dayStartHour: 7,
            dayStartMinute: 45
        )

        // 20:29 is still day
        XCTAssertFalse(config.isNightTime(hour: 20, minute: 29))
        XCTAssertEqual(config.classify(timestamp: makeDate(hour: 20, minute: 29)), .nap)

        // 20:30 is night
        XCTAssertTrue(config.isNightTime(hour: 20, minute: 30))
        XCTAssertEqual(config.classify(timestamp: makeDate(hour: 20, minute: 30)), .nightSleep)

        // 07:44 is night
        XCTAssertTrue(config.isNightTime(hour: 7, minute: 44))
        XCTAssertEqual(config.classify(timestamp: makeDate(hour: 7, minute: 44)), .nightSleep)

        // 07:45 is day
        XCTAssertFalse(config.isNightTime(hour: 7, minute: 45))
        XCTAssertEqual(config.classify(timestamp: makeDate(hour: 7, minute: 45)), .nap)
    }

    func testDurationCalculations() {
        // 20:30 to 08:00
        let config = SleepScheduleConfiguration(
            nightStartHour: 20,
            nightStartMinute: 30,
            dayStartHour: 8,
            dayStartMinute: 0
        )

        // Night is 3.5h before midnight + 8h after midnight = 11.5 hours = 41400s
        XCTAssertEqual(config.nightWindowDuration, 11.5 * 3600, accuracy: 1.0)
        // Day is 24 - 11.5 = 12.5 hours = 45000s
        XCTAssertEqual(config.dayWindowDuration, 12.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(config.nightWindowDuration + config.dayWindowDuration, 24 * 3600, accuracy: 1.0)

        XCTAssertEqual(config.nightStartTimeString, "20:30")
        XCTAssertEqual(config.dayStartTimeString, "08:00")
        XCTAssertEqual(SleepScheduleConfiguration.formatDurationText(config.nightWindowDuration), "11h 30m")
    }

    // MARK: - Persistence Tests

    func testPersistenceAndReset() {
        let custom = SleepScheduleConfiguration(
            nightStartHour: 21,
            nightStartMinute: 15,
            dayStartHour: 8,
            dayStartMinute: 30
        )

        configManager.save(custom)
        XCTAssertEqual(configManager.configuration, custom)

        // New manager instance reading same user defaults
        let newManager = SleepConfigurationManager(userDefaults: userDefaults)
        XCTAssertEqual(newManager.configuration, custom)

        // Reset
        configManager.resetToDefaults()
        XCTAssertEqual(configManager.configuration, SleepScheduleConfiguration.standard)
    }

    // MARK: - Reclassification Tests

    func testReclassificationOfUnspecifiedEvents() throws {
        // Configure schedule: night starts at 20:00, day starts at 07:00
        let config = SleepScheduleConfiguration(
            nightStartHour: 20,
            nightStartMinute: 0,
            dayStartHour: 7,
            dayStartMinute: 0
        )
        configManager.save(config)

        let afternoonDate = makeDate(hour: 15, minute: 0)
        let eveningDate = makeDate(hour: 21, minute: 0)

        let event1 = SleepEvent(type: .sleep, timestamp: afternoonDate, classification: .unspecified)
        let event2 = SleepEvent(type: .sleep, timestamp: eveningDate, classification: .unspecified)
        let event3 = SleepEvent(type: .sleep, timestamp: afternoonDate, classification: .nightSleep) // already explicit

        try database.insertEvent(event1)
        try database.insertEvent(event2)
        try database.insertEvent(event3)

        let updatedCount = try configManager.reclassifyUnspecifiedEvents(database: database)
        XCTAssertEqual(updatedCount, 2)

        let fetched = try database.fetchAllEvents(ascending: true)
        let updatedE1 = fetched.first { $0.id == event1.id }
        let updatedE2 = fetched.first { $0.id == event2.id }
        let untouchedE3 = fetched.first { $0.id == event3.id }

        XCTAssertEqual(updatedE1?.classification, .nap)
        XCTAssertEqual(updatedE2?.classification, .nightSleep)
        XCTAssertEqual(untouchedE3?.classification, .nightSleep)
    }

    // MARK: - 24-Hour Dynamic Cycle & Retroactive Recalculation Tests

    func testCycleRangeBoundariesAndNavigationLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let locale = Locale(identifier: "es_ES")
        let config = SleepScheduleConfiguration.standard // 19:00 -> 07:00

        // Before 19:00 on Nov 20 -> belongs to [Nov 19 19:00, Nov 20 19:00)
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 17, minute: 30))!
        let currentCycle = config.cycleRange(containing: afternoon, calendar: calendar)
        XCTAssertEqual(currentCycle.start, calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 19, minute: 0))!)
        XCTAssertEqual(currentCycle.end, calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 19, minute: 0))!)
        XCTAssertEqual(currentCycle.dayStart, calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 7, minute: 0))!)
        XCTAssertTrue(currentCycle.contains(currentCycle.start))
        XCTAssertFalse(currentCycle.contains(currentCycle.end))

        // At exact 19:00 on Nov 20 -> starts new cycle [Nov 20 19:00, Nov 21 19:00)
        let exactBoundary = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 19, minute: 0))!
        let nextCycle = config.cycleRange(containing: exactBoundary, calendar: calendar)
        XCTAssertEqual(nextCycle.start, exactBoundary)
        XCTAssertEqual(nextCycle.end, calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 19, minute: 0))!)

        // Offsets and navigation labels
        let prevCycle = config.cycleRange(offset: -1, from: afternoon, calendar: calendar)
        XCTAssertEqual(prevCycle.start, calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 19, minute: 0))!)
        XCTAssertEqual(prevCycle.end, calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 19, minute: 0))!)

        XCTAssertEqual(currentCycle.navigationTitle(forOffset: 0, calendar: calendar, locale: locale), "Ciclo actual")
        XCTAssertEqual(prevCycle.navigationTitle(forOffset: -1, calendar: calendar, locale: locale), "Ciclo anterior")
        XCTAssertTrue(currentCycle.navigationSubtitle(forOffset: 0, calendar: calendar, locale: locale).contains("19:00"))
        XCTAssertTrue(currentCycle.navigationSubtitle(forOffset: 0, calendar: calendar, locale: locale).contains("18:59"))

        let olderCycle = config.cycleRange(offset: -2, from: afternoon, calendar: calendar)
        XCTAssertTrue(olderCycle.navigationSubtitle(forOffset: -2, calendar: calendar, locale: locale).contains("Ciclo 24h · 19:00 – 18:59"))
    }

    func testEventsAndMetricsGroupedByCustom24HourCycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let config = SleepScheduleConfiguration.standard // 19:00 -> 07:00
        configManager.save(config)

        // Cycle 1: [Nov 18 19:00, Nov 19 19:00)
        // Night sleep: Nov 18 20:00 -> Nov 19 07:00 (11h)
        // Nap: Nov 19 13:00 -> Nov 19 14:30 (1.5h)
        // Boundary event at Nov 19 19:00:00 belongs ONLY to Cycle 2
        let c1NightStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 20, minute: 0))!
        let c1MorningWake = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 7, minute: 0))!
        let c1NapStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 13, minute: 0))!
        let c1NapEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 14, minute: 30))!
        let c2BoundarySleep = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 19, minute: 0))!
        let c2MorningWake = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 6, minute: 30))!

        try service.recordEvent(type: .sleep, timestamp: c1NightStart, force: true)
        try service.recordEvent(type: .wake, timestamp: c1MorningWake, force: true)
        try service.recordEvent(type: .sleep, timestamp: c1NapStart, force: true)
        try service.recordEvent(type: .wake, timestamp: c1NapEnd, force: true)
        try service.recordEvent(type: .sleep, timestamp: c2BoundarySleep, force: true)
        try service.recordEvent(type: .wake, timestamp: c2MorningWake, force: true)

        let cycle1 = config.cycleRange(containing: c1NapStart, calendar: calendar)
        let cycle1Events = try service.fetchEvents(in: cycle1)
        XCTAssertEqual(cycle1Events.count, 4)
        XCTAssertFalse(cycle1Events.contains { $0.timestamp == c2BoundarySleep })

        let cycle1Metrics = try service.calculateCycleMetrics(for: cycle1, calendar: calendar, configuration: config)
        XCTAssertEqual(cycle1Metrics.nightSleepOnset, c1NightStart)
        XCTAssertEqual(cycle1Metrics.morningWakeTime, c1MorningWake)
        XCTAssertEqual(cycle1Metrics.totalNightSleepDuration, 11 * 3600, accuracy: 1.0)
        XCTAssertEqual(cycle1Metrics.totalDaytimeSleepDuration, 1.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(cycle1Metrics.completedNapsCount, 1)
        XCTAssertEqual(cycle1Metrics.sleepIntervals.count, 2)

        let cycle2 = config.cycleRange(containing: c2BoundarySleep, calendar: calendar)
        let cycle2Events = try service.fetchEvents(in: cycle2)
        XCTAssertEqual(cycle2Events.count, 2)
        XCTAssertEqual(cycle2Events.first?.timestamp, c2BoundarySleep)

        let cycle2Metrics = try service.calculateCycleMetrics(for: cycle2, calendar: calendar, configuration: config)
        XCTAssertEqual(cycle2Metrics.nightSleepOnset, c2BoundarySleep)
        XCTAssertEqual(cycle2Metrics.morningWakeTime, c2MorningWake)
        XCTAssertEqual(cycle2Metrics.totalNightSleepDuration, 11.5 * 3600, accuracy: 1.0)
    }

    func testScheduleChangeRetroactivelyRecalculatesAllHistoricalCycles() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        // Start with 19:00 - 07:00
        let initialConfig = SleepScheduleConfiguration(nightStartHour: 19, nightStartMinute: 0, dayStartHour: 7, dayStartMinute: 0)
        configManager.save(initialConfig)

        // Historical sleep starting at 18:30 on Nov 16 -> 06:30 on Nov 17
        // Under 19:00-07:00, 18:30 is classified as .nap and starts in [Nov 15 19:00, Nov 16 19:00)
        let pastSleepStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 18, minute: 30))!
        let pastSleepEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 6, minute: 30))!

        // Current cycle sleep starting at 18:15 on Nov 20 -> 06:00 on Nov 21
        let recentSleepStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 18, minute: 15))!
        let recentSleepEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 6, minute: 0))!

        let pastSleepEvent = try service.recordEvent(type: .sleep, timestamp: pastSleepStart, force: true)
        try service.recordEvent(type: .wake, timestamp: pastSleepEnd, force: true)
        let recentSleepEvent = try service.recordEvent(type: .sleep, timestamp: recentSleepStart, force: true)
        try service.recordEvent(type: .wake, timestamp: recentSleepEnd, force: true)

        XCTAssertEqual(pastSleepEvent.classification, .nap)
        XCTAssertEqual(recentSleepEvent.classification, .nap)

        // User changes schedule in Settings to 18:00 - 06:00
        let updatedConfig = SleepScheduleConfiguration(nightStartHour: 18, nightStartMinute: 0, dayStartHour: 6, dayStartMinute: 0)
        let reclassifiedCount = try service.applyScheduleConfiguration(updatedConfig, calendar: calendar)

        XCTAssertEqual(configManager.configuration, updatedConfig)
        XCTAssertEqual(reclassifiedCount, 2)

        // Persisted classifications in DB are updated retroactively
        let allEvents = try database.fetchAllEvents(ascending: true)
        XCTAssertEqual(allEvents.first { $0.id == pastSleepEvent.id }?.classification, .nightSleep)
        XCTAssertEqual(allEvents.first { $0.id == recentSleepEvent.id }?.classification, .nightSleep)

        // Past cycle [Nov 16 18:00, Nov 17 18:00) now contains the entire 18:30 -> 06:30 night sleep
        let pastCycle = updatedConfig.cycleRange(containing: pastSleepStart, calendar: calendar)
        XCTAssertEqual(pastCycle.start, calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 18, minute: 0))!)
        let pastMetrics = try service.calculateCycleMetrics(for: pastCycle, calendar: calendar)
        XCTAssertEqual(pastMetrics.nightSleepOnset, pastSleepStart)
        XCTAssertEqual(pastMetrics.morningWakeTime, pastSleepEnd)
        XCTAssertEqual(pastMetrics.totalNightSleepDuration, 12 * 3600, accuracy: 1.0)
        XCTAssertEqual(pastMetrics.totalDaytimeSleepDuration, 0, accuracy: 1.0)
        XCTAssertEqual(pastMetrics.sleepIntervals.first?.classification, .nightSleep)

        // Recent cycle [Nov 20 18:00, Nov 21 18:00) also reflects the new schedule
        let recentCycle = updatedConfig.cycleRange(containing: recentSleepStart, calendar: calendar)
        let recentMetrics = try service.calculateCycleMetrics(for: recentCycle, calendar: calendar)
        XCTAssertEqual(recentMetrics.nightSleepOnset, recentSleepStart)
        XCTAssertEqual(recentMetrics.morningWakeTime, recentSleepEnd)
        XCTAssertEqual(recentMetrics.totalNightSleepDuration, 11.75 * 3600, accuracy: 1.0)
        XCTAssertEqual(recentMetrics.sleepIntervals.first?.classification, .nightSleep)
    }

    func testCrossCycleDetectionAndInformativeMessageForNapNightAndOngoingIntervals() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let locale = Locale(identifier: "es_ES")
        let config = SleepScheduleConfiguration.standard // 19:00 -> 07:00

        // 1. Same-cycle night sleep (20:30 -> 06:30 next morning) -> NOT cross-cycle
        let sameCycleStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 20, minute: 30))!
        let sameCycleEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 6, minute: 30))!
        let sameCycleInterval = SleepInterval(
            startEvent: SleepEvent(type: .sleep, timestamp: sameCycleStart, classification: .nightSleep),
            endEvent: SleepEvent(type: .wake, timestamp: sameCycleEnd),
            classification: .nightSleep
        )
        XCTAssertNil(config.crossCycleInfo(for: sameCycleInterval, calendar: calendar))

        // 2. Exact boundary end (18:00 -> 19:00) -> NOT cross-cycle
        let exactStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 18, minute: 0))!
        let exactEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 19, minute: 0))!
        let exactBoundaryInterval = SleepInterval(
            startEvent: SleepEvent(type: .sleep, timestamp: exactStart, classification: .nap),
            endEvent: SleepEvent(type: .wake, timestamp: exactEnd),
            classification: .nap
        )
        XCTAssertNil(config.crossCycleInfo(for: exactBoundaryInterval, calendar: calendar))

        // 3. Cross-cycle nap (Nov 20 18:00 -> Nov 20 20:00)
        let napCrossEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20, minute: 0))!
        let napCrossInterval = SleepInterval(
            startEvent: SleepEvent(type: .sleep, timestamp: exactStart, classification: .nap),
            endEvent: SleepEvent(type: .wake, timestamp: napCrossEnd),
            classification: .nap
        )
        let napInfo = config.crossCycleInfo(for: napCrossInterval, calendar: calendar)
        XCTAssertNotNil(napInfo)
        XCTAssertEqual(napInfo?.isOngoing, false)
        XCTAssertEqual(napInfo?.totalDuration ?? 0, 2 * 3600, accuracy: 1.0)
        let napMessage = napInfo?.detailMessage(calendar: calendar, locale: locale) ?? ""
        XCTAssertTrue(napMessage.contains("siesta"))
        XCTAssertFalse(napMessage.contains("Ciclo de inicio:"))
        XCTAssertFalse(napMessage.contains("Ciclo de fin:"))
        XCTAssertTrue(napMessage.contains("Inicio:"))
        XCTAssertTrue(napMessage.contains("Fin:"))
        XCTAssertTrue(napMessage.contains("18:00"))
        XCTAssertTrue(napMessage.contains("20:00"))
        XCTAssertTrue(napMessage.contains("2h 0m"))
        XCTAssertTrue(napMessage.contains("Se durmió"))
        XCTAssertTrue(napMessage.contains("Se despertó"))
        XCTAssertTrue(napMessage.hasSuffix("correspondientes a este intervalo."))

        // 4. Cross-cycle night sleep (Nov 19 20:00 -> Nov 20 21:00 = 25h)
        let nightCrossStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 20, minute: 0))!
        let nightCrossEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 21, minute: 0))!
        let nightCrossInterval = SleepInterval(
            startEvent: SleepEvent(type: .sleep, timestamp: nightCrossStart, classification: .nightSleep),
            endEvent: SleepEvent(type: .wake, timestamp: nightCrossEnd),
            classification: .nightSleep
        )
        let nightInfo = config.crossCycleInfo(for: nightCrossInterval, calendar: calendar)
        XCTAssertNotNil(nightInfo)
        XCTAssertEqual(nightInfo?.totalDuration ?? 0, 25 * 3600, accuracy: 1.0)
        let nightMessage = nightInfo?.detailMessage(calendar: calendar, locale: locale) ?? ""
        XCTAssertTrue(nightMessage.contains("sueño nocturno"))
        XCTAssertTrue(nightMessage.contains("25h 0m"))

        // 5. Ongoing interval crossing into next cycle (Nov 20 18:00, ongoing at Nov 20 20:30)
        let nowLaterCycle = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20, minute: 30))!
        let ongoingInterval = SleepInterval(
            startEvent: SleepEvent(type: .sleep, timestamp: exactStart, classification: .nap),
            endEvent: nil,
            classification: .nap
        )
        let ongoingInfo = config.crossCycleInfo(for: ongoingInterval, now: nowLaterCycle, calendar: calendar)
        XCTAssertNotNil(ongoingInfo)
        XCTAssertEqual(ongoingInfo?.isOngoing, true)
        XCTAssertEqual(ongoingInfo?.totalDuration ?? 0, 2.5 * 3600, accuracy: 1.0)
        let ongoingMessage = ongoingInfo?.detailMessage(calendar: calendar, locale: locale) ?? ""
        XCTAssertTrue(ongoingMessage.contains("En curso"))
        XCTAssertTrue(ongoingMessage.contains("2h 30m"))
        XCTAssertFalse(ongoingMessage.contains("Ciclo actual:"))

        // 6. Interval display range omits duplicated duration and includes dates only when crossing cycles
        XCTAssertEqual(sameCycleInterval.rangeText(includeDate: false, calendar: calendar, locale: locale), "20:30 - 06:30")
        let crossRangeText = nightCrossInterval.rangeText(includeDate: true, calendar: calendar, locale: locale)
        XCTAssertTrue(crossRangeText.contains("19"))
        XCTAssertTrue(crossRangeText.contains("20:00"))
        XCTAssertTrue(crossRangeText.contains("20"))
        XCTAssertTrue(crossRangeText.contains("21:00"))
        XCTAssertFalse(crossRangeText.contains("25h"))
        XCTAssertTrue(ongoingInterval.rangeText(includeDate: true, calendar: calendar, locale: locale).hasSuffix("- Ahora"))
    }

    func testActiveOngoingSleepIntervalAppearsOnlyInCurrentCycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let config = SleepScheduleConfiguration.standard // 19:00 -> 07:00
        configManager.save(config)

        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 30))!
        let currentCycle = config.cycleRange(containing: now, calendar: calendar) // [Nov 20 19:00, Nov 21 19:00)
        let previousCycle = config.cycleRange(offset: -1, from: now, calendar: calendar) // [Nov 19 19:00, Nov 20 19:00)

        // Ongoing sleep started in previous cycle at 18:15 and is still active at 22:30
        let ongoingStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 18, minute: 15))!
        let ongoingEvent = try service.recordEvent(type: .sleep, timestamp: ongoingStart, force: true)

        let inCurrent = try service.activeSleepInterval(in: currentCycle, configuration: config, now: now, calendar: calendar)
        XCTAssertNotNil(inCurrent)
        XCTAssertEqual(inCurrent?.id, ongoingEvent.id)
        XCTAssertFalse(inCurrent?.isCompleted ?? true)
        XCTAssertEqual(inCurrent?.classification, .nap)
        XCTAssertNotNil(config.crossCycleInfo(for: inCurrent!, now: now, calendar: calendar))

        // Must NOT appear in previous cycle
        let inPrevious = try service.activeSleepInterval(in: previousCycle, configuration: config, now: now, calendar: calendar)
        XCTAssertNil(inPrevious)

        // Once baby wakes up, no active ongoing interval remains
        let wakeTime = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 22, minute: 0))!
        try service.recordEvent(type: .wake, timestamp: wakeTime, force: true)
        XCTAssertNil(try service.activeSleepInterval(in: currentCycle, configuration: config, now: now, calendar: calendar))
    }

    // MARK: - Helpers

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}
