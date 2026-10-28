import XCTest

final class SleepIntervalTests: XCTestCase {
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

    func testSingleCompletedNapDuration() throws {
        let baseDate = Date()
        let sleepTime = baseDate
        let wakeTime = baseDate.addingTimeInterval(5400) // 1 hour 30 mins

        let sleepEvent = SleepEvent(type: .sleep, timestamp: sleepTime, classification: .nap)
        let wakeEvent = SleepEvent(type: .wake, timestamp: wakeTime)

        let (sleeps, _) = service.computeIntervals(from: [sleepEvent, wakeEvent])

        XCTAssertEqual(sleeps.count, 1)
        let interval = sleeps[0]
        XCTAssertTrue(interval.isCompleted)
        XCTAssertEqual(interval.duration, 5400, accuracy: 0.1)
        XCTAssertEqual(interval.formattedDuration, "1h 30m")
        XCTAssertEqual(interval.classification, .nap)
    }

    func testIncompleteActiveSleepInterval() throws {
        let sleepTime = Date().addingTimeInterval(-1800) // 30 mins ago
        let sleepEvent = SleepEvent(type: .sleep, timestamp: sleepTime, classification: .nap)

        let (sleeps, _) = service.computeIntervals(from: [sleepEvent])

        XCTAssertEqual(sleeps.count, 1)
        let interval = sleeps[0]
        XCTAssertFalse(interval.isCompleted)
        XCTAssertNil(interval.endTime)
        XCTAssertGreaterThanOrEqual(interval.duration, 1800)
    }

    func testAwakeIntervalBetweenNaps() throws {
        let t0 = Date()
        let nap1Sleep = SleepEvent(type: .sleep, timestamp: t0)
        let nap1Wake = SleepEvent(type: .wake, timestamp: t0.addingTimeInterval(3600)) // 1h sleep
        let nap2Sleep = SleepEvent(type: .sleep, timestamp: t0.addingTimeInterval(9000)) // 1.5h awake
        let nap2Wake = SleepEvent(type: .wake, timestamp: t0.addingTimeInterval(12600))

        let (sleeps, awakes) = service.computeIntervals(from: [nap1Sleep, nap1Wake, nap2Sleep, nap2Wake])

        XCTAssertEqual(sleeps.count, 2)
        // 1 completed awake window between naps + 1 active ongoing awake window after nap2
        XCTAssertEqual(awakes.count, 2)

        let completedAwake = awakes[0]
        XCTAssertEqual(completedAwake.duration, 5400, accuracy: 0.1) // 1h 30m wake window
        XCTAssertEqual(completedAwake.formattedDuration, "1h 30m")
        XCTAssertNotNil(completedAwake.nextSleepEvent)

        let activeAwake = awakes[1]
        XCTAssertNil(activeAwake.nextSleepEvent)
    }
}
