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

    func testOvernightSleepCrossingMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        // Day 1: 2026-10-27
        let day1Components = DateComponents(year: 2026, month: 10, day: 27, hour: 20, minute: 0, second: 0)
        let routineTime = calendar.date(from: day1Components)!
        let sleepTime = calendar.date(byAdding: .minute, value: 30, to: routineTime)! // 20:30

        // Day 2: 2026-10-28 06:30
        let day2WakeComponents = DateComponents(year: 2026, month: 10, day: 28, hour: 6, minute: 30, second: 0)
        let wakeTime = calendar.date(from: day2WakeComponents)!

        try database.insertEvent(SleepEvent(type: .bedtimeRoutineStart, timestamp: routineTime))
        try database.insertEvent(SleepEvent(type: .sleep, timestamp: sleepTime, classification: .nightSleep))
        try database.insertEvent(SleepEvent(type: .wake, timestamp: wakeTime))

        // Check Day 1 metrics
        let day1Metrics = try service.calculateDayMetrics(for: routineTime, calendar: calendar)
        XCTAssertEqual(day1Metrics.bedtimeRoutineStart, routineTime)
        XCTAssertEqual(day1Metrics.nightSleepOnset, sleepTime)
        XCTAssertEqual(day1Metrics.routineToSleepDuration, 1800) // 30 minutes

        // Sleep duration on Day 1 is from 20:30 to 24:00 (3.5 hours = 12600s)
        XCTAssertEqual(day1Metrics.totalNightSleepDuration, 12600, accuracy: 1.0)

        // Check Day 2 metrics
        let day2Metrics = try service.calculateDayMetrics(for: wakeTime, calendar: calendar)
        XCTAssertEqual(day2Metrics.morningWakeTime, wakeTime)
        // Sleep duration on Day 2 from 00:00 to 06:30 (6.5 hours = 23400s)
        XCTAssertEqual(day2Metrics.totalNightSleepDuration, 23400, accuracy: 1.0)

        // Combined interval
        let (sleeps, _) = service.computeIntervals(from: try database.fetchAllEvents())
        XCTAssertEqual(sleeps.count, 1)
        XCTAssertEqual(sleeps[0].duration, 10 * 3600, accuracy: 1.0) // 20:30 to 06:30 = 10h
    }
}
