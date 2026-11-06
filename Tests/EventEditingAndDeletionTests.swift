import XCTest

final class EventEditingAndDeletionTests: XCTestCase {
    private var tempDirectory: URL!
    private var database: SQLiteDatabase!
    private var service: SleepTrackingService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let dbURL = tempDirectory.appendingPathComponent("test.sqlite3")
        database = try SQLiteDatabase(url: dbURL)
        service = SleepTrackingService(database: database)
    }

    override func tearDownWithError() throws {
        database = nil
        service = nil
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Event Editing (Tap to Edit) Tests

    func testUpdateEventUpdatesFieldsAndRecalculatesMetrics() throws {
        let originalDate = Date().addingTimeInterval(-7200)
        let event = SleepEvent(
            type: .sleep,
            timestamp: originalDate,
            classification: .nap,
            notes: "Notas iniciales"
        )
        try service.recordEvent(
            type: event.type,
            timestamp: event.timestamp,
            classification: event.classification,
            notes: event.notes,
            force: true
        )

        let fetchedEvents = try service.fetchEvents(for: originalDate)
        XCTAssertEqual(fetchedEvents.count, 1)
        let recordedEvent = fetchedEvents[0]
        XCTAssertEqual(recordedEvent.notes, "Notas iniciales")
        XCTAssertEqual(recordedEvent.classification, .nap)

        // Simulate user editing event via tap-to-edit
        let newDate = originalDate.addingTimeInterval(300)
        var updatedEvent = recordedEvent
        updatedEvent.timestamp = newDate
        updatedEvent.classification = .nightSleep
        updatedEvent.notes = "Notas editadas tras tap"

        try service.updateEvent(updatedEvent)

        let updatedEvents = try service.fetchEvents(for: newDate)
        XCTAssertEqual(updatedEvents.count, 1)
        let refreshed = updatedEvents[0]
        XCTAssertEqual(refreshed.id, recordedEvent.id)
        XCTAssertEqual(refreshed.timestamp.timeIntervalSince1970, newDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(refreshed.classification, .nightSleep)
        XCTAssertEqual(refreshed.notes, "Notas editadas tras tap")
        XCTAssertGreaterThanOrEqual(refreshed.updatedAt, refreshed.createdAt)
    }

    func testUpdateEventSafelyHandlesNonExistentId() throws {
        let nonExistentEvent = SleepEvent(
            id: UUID(),
            type: .sleep,
            timestamp: Date(),
            classification: .nap,
            notes: "Non-existent"
        )

        // Should not throw or crash
        XCTAssertNoThrow(try service.updateEvent(nonExistentEvent))
        let events = try service.fetchEvents(for: Date())
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Event Deletion (Swipe to Delete) Tests

    func testDeleteEventRemovesFromDatabase() throws {
        let date = Date().addingTimeInterval(-3600)
        try service.recordEvent(type: .sleep, timestamp: date, force: true)

        let initialEvents = try service.fetchEvents(for: date)
        XCTAssertEqual(initialEvents.count, 1)
        let eventId = initialEvents[0].id

        // Perform deletion (swipe to delete action)
        try service.deleteEvent(id: eventId)

        let remainingEvents = try service.fetchEvents(for: date)
        XCTAssertTrue(remainingEvents.isEmpty)
    }

    func testDeleteEventRecomputesSleepIntervalsCorrectly() throws {
        let baseTime = Date().addingTimeInterval(-7200)
        let sleepTime = baseTime
        let wakeTime = baseTime.addingTimeInterval(3600) // 1h nap

        try service.recordEvent(type: .sleep, timestamp: sleepTime, classification: .nap, force: true)
        try service.recordEvent(type: .wake, timestamp: wakeTime, force: true)

        var metrics = try service.calculateDayMetrics(for: baseTime)
        XCTAssertEqual(metrics.sleepIntervals.count, 1)
        XCTAssertTrue(metrics.sleepIntervals[0].isCompleted)
        XCTAssertEqual(metrics.sleepIntervals[0].duration, 3600, accuracy: 1.0)

        // Delete the wake event -> interval becomes in-progress
        let events = try service.fetchEvents(for: baseTime)
        let wakeEvent = events.first { $0.type == .wake }!
        try service.deleteEvent(id: wakeEvent.id)

        metrics = try service.calculateDayMetrics(for: baseTime)
        XCTAssertEqual(metrics.sleepIntervals.count, 1)
        XCTAssertFalse(metrics.sleepIntervals[0].isCompleted)

        // Delete the sleep event -> intervals become empty
        let remainingEvents = try service.fetchEvents(for: baseTime)
        let sleepEvent = remainingEvents.first { $0.type == .sleep }!
        try service.deleteEvent(id: sleepEvent.id)

        metrics = try service.calculateDayMetrics(for: baseTime)
        XCTAssertEqual(metrics.sleepIntervals.count, 0)
    }

    func testDeleteNonExistentEventDoesNotAffectExistingEvents() throws {
        let date = Date()
        try service.recordEvent(type: .sleep, timestamp: date, force: true)

        let randomId = UUID()
        XCTAssertNoThrow(try service.deleteEvent(id: randomId))

        let remainingEvents = try service.fetchEvents(for: date)
        XCTAssertEqual(remainingEvents.count, 1)
    }

    // MARK: - Notification on Data Change Tests

    func testNotificationBroadcastOnUpdateAndDelete() throws {
        let event = SleepEvent(type: .sleep, timestamp: Date())
        try service.recordEvent(type: event.type, timestamp: event.timestamp, force: true)
        let recorded = (try service.fetchEvents(for: Date())).first!

        let expectationUpdate = expectation(forNotification: .sleepEventsDidChange, object: nil)
        var updated = recorded
        updated.notes = "New note"
        try service.updateEvent(updated)
        wait(for: [expectationUpdate], timeout: 2.0)

        let expectationDelete = expectation(forNotification: .sleepEventsDidChange, object: nil)
        try service.deleteEvent(id: recorded.id)
        wait(for: [expectationDelete], timeout: 2.0)
    }
}
