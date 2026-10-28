import XCTest

final class DuplicateHandlingTests: XCTestCase {
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

    func testConsecutiveSleepThrowsError() throws {
        let now = Date()
        try service.recordEvent(type: .sleep, timestamp: now)

        // Attempting to sleep again after 10 minutes should throw alreadySleeping
        XCTAssertThrowsError(
            try service.recordEvent(type: .sleep, timestamp: now.addingTimeInterval(600))
        ) { error in
            guard let sleepError = error as? SleepTrackingError,
                  case .alreadySleeping = sleepError else {
                XCTFail("Expected alreadySleeping error, got \(error)")
                return
            }
        }
    }

    func testRapidDebounceWithin5SecondsReturnsSameEvent() throws {
        let now = Date()
        let first = try service.recordEvent(type: .sleep, timestamp: now)
        // Rapid double tap 1 second later
        let second = try service.recordEvent(type: .sleep, timestamp: now.addingTimeInterval(1))

        XCTAssertEqual(first.id, second.id)
        let events = try database.fetchAllEvents()
        XCTAssertEqual(events.count, 1)
    }

    func testConsecutiveWakeThrowsError() throws {
        let now = Date()
        try service.recordEvent(type: .sleep, timestamp: now.addingTimeInterval(-3600))
        try service.recordEvent(type: .wake, timestamp: now)

        // Attempting to wake again should throw alreadyAwake
        XCTAssertThrowsError(
            try service.recordEvent(type: .wake, timestamp: now.addingTimeInterval(300))
        ) { error in
            guard let sleepError = error as? SleepTrackingError,
                  case .alreadyAwake = sleepError else {
                XCTFail("Expected alreadyAwake error, got \(error)")
                return
            }
        }
    }

    func testForceRecordAllowsCorrection() throws {
        let now = Date()
        try service.recordEvent(type: .sleep, timestamp: now)
        // With force = true, user can override/correct sequence
        let forced = try service.recordEvent(type: .sleep, timestamp: now.addingTimeInterval(60), force: true)

        let events = try database.fetchAllEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last?.id, forced.id)
    }
}
