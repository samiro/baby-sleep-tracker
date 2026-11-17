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
        service = SleepTrackingService(database: database)

        let suiteName = "test_suite_\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        configManager = SleepConfigurationManager(userDefaults: userDefaults)
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

    // MARK: - Helpers

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}
