import XCTest

final class OvernightBoundaryTests: XCTestCase {
    var tempDirectory: URL!
    var database: SQLiteDatabase!
    var service: SleepTrackingService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let dbURL = tempDirectory.appendingPathComponent("test.sqlite3")
        database = try SQLiteDatabase(url: dbURL)
        service = SleepTrackingService(database: database)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testOvernightSleepStaysUnifiedWithin24HourCycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let standardConfig = SleepScheduleConfiguration.standard // 19:00 -> 07:00

        // Night sleep inside cycle [Oct 27 19:00, Oct 28 19:00):
        // 2026-10-27 20:30 to 2026-10-28 06:30 (10 hours)
        let sleepTime = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 20, minute: 30, second: 0))!
        let wakeTime = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 6, minute: 30, second: 0))!

        try database.insertEvent(SleepEvent(type: .sleep, timestamp: sleepTime, classification: .nightSleep))
        try database.insertEvent(SleepEvent(type: .wake, timestamp: wakeTime))

        // Both sleepTime (Oct 27 20:30) and wakeTime (Oct 28 06:30) resolve to the SAME 24h cycle
        let metricsFromSleep = try service.calculateDayMetrics(for: sleepTime, calendar: calendar, configuration: standardConfig)
        let metricsFromWake = try service.calculateDayMetrics(for: wakeTime, calendar: calendar, configuration: standardConfig)

        XCTAssertEqual(metricsFromSleep.cycleStart, metricsFromWake.cycleStart)
        XCTAssertEqual(metricsFromSleep.cycleEnd, metricsFromWake.cycleEnd)
        XCTAssertEqual(metricsFromSleep.nightSleepOnset, sleepTime)
        XCTAssertEqual(metricsFromSleep.morningWakeTime, wakeTime)
        XCTAssertEqual(metricsFromSleep.totalNightSleepDuration, 10 * 3600, accuracy: 1.0)
        XCTAssertEqual(metricsFromSleep.sleepIntervals.count, 1)

        // Combined interval
        let (sleeps, _) = service.computeIntervals(from: try database.fetchAllEvents())
        XCTAssertEqual(sleeps.count, 1)
        XCTAssertEqual(sleeps[0].duration, 10 * 3600, accuracy: 1.0) // 20:30 to 06:30 = 10h
    }

    func testSleepCrossingCycleBoundaryClipsAtConfiguredBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let standardConfig = SleepScheduleConfiguration.standard // 19:00 -> 07:00

        // Sleep starts at 18:00 (end of previous cycle) and ends at 20:00 (start of next cycle)
        let sleepTime = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 18, minute: 0, second: 0))!
        let wakeTime = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 20, minute: 0, second: 0))!

        try database.insertEvent(SleepEvent(type: .sleep, timestamp: sleepTime, classification: .nap))
        try database.insertEvent(SleepEvent(type: .wake, timestamp: wakeTime))

        let previousCycleMetrics = try service.calculateDayMetrics(for: sleepTime, calendar: calendar, configuration: standardConfig)
        let nextCycleMetrics = try service.calculateDayMetrics(for: wakeTime, calendar: calendar, configuration: standardConfig)

        XCTAssertNotEqual(previousCycleMetrics.cycleStart, nextCycleMetrics.cycleStart)
        // 18:00 to 19:00 = 1h in previous cycle, counted in both interval list and summary
        XCTAssertEqual(previousCycleMetrics.sleepIntervals.count, 1)
        XCTAssertEqual(previousCycleMetrics.completedNapsCount, 1)
        XCTAssertEqual(previousCycleMetrics.totalDaytimeSleepDuration, 3600, accuracy: 1.0)
        XCTAssertEqual(previousCycleMetrics.totalSleepDuration, 3600, accuracy: 1.0)
        // 19:00 to 20:00 = 1h in next cycle, also counted in both interval list and summary
        XCTAssertEqual(nextCycleMetrics.sleepIntervals.count, 1)
        XCTAssertEqual(nextCycleMetrics.completedNapsCount, 1)
        XCTAssertEqual(nextCycleMetrics.totalDaytimeSleepDuration, 3600, accuracy: 1.0)
        XCTAssertEqual(nextCycleMetrics.totalSleepDuration, 3600, accuracy: 1.0)
    }
}
