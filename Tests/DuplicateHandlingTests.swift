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

    func testConsecutiveSleepIsAllowedWithoutBlocking() throws {
        let now = Date()
        let first = try service.recordEvent(type: .sleep, timestamp: now)

        // Attempting to sleep again after 10 minutes should succeed without throwing
        let second = try service.recordEvent(type: .sleep, timestamp: now.addingTimeInterval(600))

        XCTAssertNotEqual(first.id, second.id)
        let events = try database.fetchAllEvents()
        XCTAssertEqual(events.count, 2)
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

    func testConsecutiveWakeIsAllowedWithoutBlocking() throws {
        let now = Date()
        try service.recordEvent(type: .sleep, timestamp: now.addingTimeInterval(-3600))
        let firstWake = try service.recordEvent(type: .wake, timestamp: now)

        // Attempting to wake again should succeed without throwing
        let secondWake = try service.recordEvent(type: .wake, timestamp: now.addingTimeInterval(300))

        XCTAssertNotEqual(firstWake.id, secondWake.id)
        let events = try database.fetchAllEvents()
        XCTAssertEqual(events.count, 3)
    }

    func testForceRecordAllowsCorrection() throws {
        let now = Date()
        try service.recordEvent(type: .sleep, timestamp: now)
        // With force = true, user can override/correct sequence even within 5 seconds
        let forced = try service.recordEvent(type: .sleep, timestamp: now.addingTimeInterval(2), force: true)

        let events = try database.fetchAllEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last?.id, forced.id)
    }
}
