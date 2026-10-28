import XCTest

final class TimezoneHandlingTests: XCTestCase {
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

    func testAbsoluteTimestampPreservedAcrossTimezones() throws {
        // Create an event at a fixed UTC epoch timestamp
        let epoch: TimeInterval = 1793134800 // 2026-10-27 21:00:00 UTC
        let date = Date(timeIntervalSince1970: epoch)

        let event = SleepEvent(type: .sleep, timestamp: date)
        try database.insertEvent(event)

        let fetched = try database.fetchEvent(id: event.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched!.timestamp.timeIntervalSince1970, epoch, accuracy: 0.001)

        // Verify representation in different timezones
        let utcFormatter = DateFormatter()
        utcFormatter.timeZone = TimeZone(identifier: "UTC")
        utcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let bogotaFormatter = DateFormatter()
        bogotaFormatter.timeZone = TimeZone(identifier: "America/Bogota") // UTC-5
        bogotaFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let madridFormatter = DateFormatter()
        madridFormatter.timeZone = TimeZone(identifier: "Europe/Madrid") // UTC+1/2
        madridFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        XCTAssertEqual(utcFormatter.string(from: fetched!.timestamp), "2026-10-27 21:00:00")
        XCTAssertEqual(bogotaFormatter.string(from: fetched!.timestamp), "2026-10-27 16:00:00")
        // On Oct 27, 2026, Madrid is CET (UTC+1, winter time)
        XCTAssertEqual(madridFormatter.string(from: fetched!.timestamp), "2026-10-27 22:00:00")
    }

    func testDurationAcrossDaylightSavingTransition() throws {
        // Daylight saving change: clocks advance by 1 hour (23 physical hours between 00:00 and 00:00)
        // Storing as absolute TimeInterval ensures duration calculation is strictly physical elapsed time
        let t0 = Date(timeIntervalSince1970: 1774742400) // 2026-03-29 00:00:00 UTC
        let t1 = Date(timeIntervalSince1970: 1774771200) // 8 hours later

        let sleep = SleepEvent(type: .sleep, timestamp: t0)
        let wake = SleepEvent(type: .wake, timestamp: t1)

        let (intervals, _) = service.computeIntervals(from: [sleep, wake])
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals[0].duration, 8 * 3600, accuracy: 0.01)
    }
}
