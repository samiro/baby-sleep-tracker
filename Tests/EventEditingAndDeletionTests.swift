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

    // MARK: - Event Creation Form Validation & Automatic Classification Tests

    func testClampedInitialTimestampPreventsFutureInitialDate() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let past = now.addingTimeInterval(-3600)
        let future = now.addingTimeInterval(86400)

        XCTAssertEqual(SleepEvent.clampedInitialTimestamp(past, now: now), past)
        XCTAssertEqual(SleepEvent.clampedInitialTimestamp(now, now: now), now)
        XCTAssertEqual(SleepEvent.clampedInitialTimestamp(future, now: now), now)
    }

    func testFormValidationRejectsFutureTimestampsAndClampsSameMinuteArtifact() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15, minute: 30, second: 10))!
        let futureDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10, minute: 0, second: 0))!
        let nextMinute = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15, minute: 31, second: 0))!
        let sameMinuteLaterSecond = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15, minute: 30, second: 45))!
        let past = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 14, minute: 0, second: 0))!

        XCTAssertThrowsError(
            try SleepEvent.makeValidatedFormEvent(
                type: .sleep,
                timestamp: futureDay,
                notes: nil,
                configuration: .standard,
                now: now,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(error as? SleepEventFormValidationError, .futureTimestamp)
        }

        XCTAssertThrowsError(
            try SleepEvent.makeValidatedFormEvent(
                type: .wake,
                timestamp: nextMinute,
                notes: nil,
                configuration: .standard,
                now: now,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(error as? SleepEventFormValidationError, .futureTimestamp)
        }

        let clampedCurrentMinute = try SleepEvent.makeValidatedFormEvent(
            type: .sleep,
            timestamp: sameMinuteLaterSecond,
            notes: "  Siesta corta  ",
            configuration: .standard,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(clampedCurrentMinute.timestamp, now)
        XCTAssertEqual(clampedCurrentMinute.notes, "Siesta corta")

        let pastEvent = try SleepEvent.makeValidatedFormEvent(
            type: .sleep,
            timestamp: past,
            notes: "   ",
            configuration: .standard,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(pastEvent.timestamp, past)
        XCTAssertNil(pastEvent.notes)
    }

    func testFormAutomaticClassificationUsesConfigured24HourCycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 59, second: 0))!
        let customConfig = SleepScheduleConfiguration(
            nightStartHour: 21,
            nightStartMinute: 0,
            dayStartHour: 6,
            dayStartMinute: 30
        )

        let earlyMorningNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 6, minute: 29))!
        let morningNap = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 6, minute: 30))!
        let eveningNapUnderCustomConfig = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 20, minute: 0))!
        let bedtimeNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 21, minute: 0))!

        let e1 = try SleepEvent.makeValidatedFormEvent(
            type: .sleep,
            timestamp: earlyMorningNight,
            notes: nil,
            configuration: customConfig,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(e1.classification, .nightSleep)

        let e2 = try SleepEvent.makeValidatedFormEvent(
            type: .sleep,
            timestamp: morningNap,
            notes: nil,
            configuration: customConfig,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(e2.classification, .nap)

        // At 20:00: standard schedule would classify as nightSleep, custom 21:00 schedule classifies as nap
        let e3Custom = try SleepEvent.makeValidatedFormEvent(
            type: .sleep,
            timestamp: eveningNapUnderCustomConfig,
            notes: nil,
            configuration: customConfig,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(e3Custom.classification, .nap)

        let e3Standard = try SleepEvent.makeValidatedFormEvent(
            type: .sleep,
            timestamp: eveningNapUnderCustomConfig,
            notes: nil,
            configuration: .standard,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(e3Standard.classification, .nightSleep)

        let e4 = try SleepEvent.makeValidatedFormEvent(
            type: .sleep,
            timestamp: bedtimeNight,
            notes: nil,
            configuration: customConfig,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(e4.classification, .nightSleep)

        // Wake events remain unspecified
        let wakeEvent = try SleepEvent.makeValidatedFormEvent(
            type: .wake,
            timestamp: bedtimeNight,
            notes: nil,
            configuration: customConfig,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(wakeEvent.classification, .unspecified)
    }

    func testFormEditingExistingEventReclassifiesAutomaticallyAndPreservesIdentity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 14, minute: 0))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 22, minute: 0))!
        let updatedNightTime = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 20, minute: 30))!

        let existing = SleepEvent(
            id: UUID(),
            type: .sleep,
            timestamp: createdAt,
            classification: .nap,
            notes: "Original",
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let edited = try SleepEvent.makeValidatedFormEvent(
            existingEvent: existing,
            type: .sleep,
            timestamp: updatedNightTime,
            notes: "Editado",
            configuration: .standard,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(edited.id, existing.id)
        XCTAssertEqual(edited.createdAt, existing.createdAt)
        XCTAssertEqual(edited.updatedAt, now)
        XCTAssertEqual(edited.timestamp, updatedNightTime)
        XCTAssertEqual(edited.classification, .nightSleep)
        XCTAssertEqual(edited.notes, "Editado")
    }
}
