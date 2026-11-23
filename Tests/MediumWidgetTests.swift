import XCTest

final class MediumWidgetTests: XCTestCase {
    private var tempDir: URL!
    private var database: SQLiteDatabase!
    private var configDefaults: UserDefaults!
    private var configSuiteName: String!
    private var configManager: SleepConfigurationManager!
    private var primaryProfileDefaults: UserDefaults!
    private var primaryProfileSuiteName: String!
    private var groupProfileDefaults: UserDefaults!
    private var groupProfileSuiteName: String!
    private var profileManager: BabyProfileManager!
    private var service: SleepTrackingService!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("widget_test.sqlite3")
        database = try SQLiteDatabase(url: dbURL)

        configSuiteName = "test_widget_config_\(UUID().uuidString)"
        configDefaults = UserDefaults(suiteName: configSuiteName)!
        configManager = SleepConfigurationManager(userDefaults: configDefaults)

        primaryProfileSuiteName = "test_widget_profile_primary_\(UUID().uuidString)"
        primaryProfileDefaults = UserDefaults(suiteName: primaryProfileSuiteName)!
        groupProfileSuiteName = "test_widget_profile_group_\(UUID().uuidString)"
        groupProfileDefaults = UserDefaults(suiteName: groupProfileSuiteName)!
        profileManager = BabyProfileManager(defaults: primaryProfileDefaults, groupDefaults: groupProfileDefaults)

        service = SleepTrackingService(database: database, configurationManager: configManager)

        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
    }

    override func tearDownWithError() throws {
        database = nil
        service = nil
        configManager = nil
        profileManager = nil
        configDefaults.removePersistentDomain(forName: configSuiteName)
        primaryProfileDefaults.removePersistentDomain(forName: primaryProfileSuiteName)
        groupProfileDefaults.removePersistentDomain(forName: groupProfileSuiteName)
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    func testPrimaryActionSwitchesDynamicallyBetweenSleepAndWake() throws {
        let now = makeDate(year: 2026, month: 11, day: 22, hour: 14, minute: 0)

        // Unknown / initial state -> single action "Se durmió"
        let emptySnapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(emptySnapshot.isSleeping)
        XCTAssertEqual(emptySnapshot.stateTitle, "Sin registro")
        XCTAssertEqual(emptySnapshot.primaryAction, .recordSleep)
        XCTAssertEqual(emptySnapshot.primaryAction.title, "Se durmió")
        XCTAssertNil(emptySnapshot.lastEvent)
        XCTAssertEqual(emptySnapshot.formattedCycleTotalSleep, "0m")

        // After recording sleep -> single action switches to "Se despertó"
        let sleepTime = makeDate(year: 2026, month: 11, day: 22, hour: 13, minute: 30)
        try service.recordEvent(type: .sleep, timestamp: sleepTime, force: true)

        let sleepingSnapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(sleepingSnapshot.isSleeping)
        XCTAssertEqual(sleepingSnapshot.stateTitle, "Durmiendo")
        XCTAssertEqual(sleepingSnapshot.primaryAction, .recordWake)
        XCTAssertEqual(sleepingSnapshot.primaryAction.title, "Se despertó")
        XCTAssertEqual(sleepingSnapshot.lastEventLabel, "Se durmió")
        XCTAssertEqual(sleepingSnapshot.formattedLastEventTime(calendar: calendar), "13:30")

        // After recording wake -> single action switches back to "Se durmió" and cycle sleep updates
        let wakeTime = makeDate(year: 2026, month: 11, day: 22, hour: 14, minute: 45)
        try service.recordEvent(type: .wake, timestamp: wakeTime, force: true)

        let awakeSnapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: makeDate(year: 2026, month: 11, day: 22, hour: 15, minute: 0),
            calendar: calendar
        )
        XCTAssertFalse(awakeSnapshot.isSleeping)
        XCTAssertEqual(awakeSnapshot.stateTitle, "Despierto")
        XCTAssertEqual(awakeSnapshot.primaryAction, .recordSleep)
        XCTAssertEqual(awakeSnapshot.primaryAction.title, "Se durmió")
        XCTAssertEqual(awakeSnapshot.lastEventLabel, "Se despertó")
        XCTAssertEqual(awakeSnapshot.formattedLastEventTime(calendar: calendar), "14:45")
        XCTAssertEqual(awakeSnapshot.cycleTotalSleepDuration, 75 * 60, accuracy: 1.0)
        XCTAssertEqual(awakeSnapshot.formattedCycleTotalSleep, "1h 15m")
    }

    func testCycleAccumulatedSleepRespectsConfigured24HourCycleNotMidnight() throws {
        // Custom 24h cycle: 20:00 -> 08:00
        let customConfig = SleepScheduleConfiguration(
            nightStartHour: 20,
            nightStartMinute: 0,
            dayStartHour: 8,
            dayStartMinute: 0
        )
        configManager.save(customConfig)

        // Previous cycle nap: Nov 21 15:00 -> 16:30 (1h 30m) -- MUST NOT count in current cycle
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 15, minute: 0), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 16, minute: 30), force: true)

        // Current cycle [Nov 21 20:00, Nov 22 20:00):
        // Night sleep starting BEFORE midnight: Nov 21 20:30 -> Nov 22 07:30 (11h)
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 20, minute: 30), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 7, minute: 30), force: true)
        // Daytime nap: Nov 22 12:00 -> 13:30 (1h 30m)
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 12, minute: 0), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 13, minute: 30), force: true)

        let now = makeDate(year: 2026, month: 11, day: 22, hour: 15, minute: 0)
        let snapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )

        // Total should be 11h + 1h 30m = 12h 30m (includes the 20:30-23:59 pre-midnight portion!)
        XCTAssertEqual(snapshot.cycleTotalSleepDuration, 12.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(snapshot.formattedCycleTotalSleep, "12h 30m")
        XCTAssertEqual(snapshot.formattedCycleWindow(calendar: calendar), "Ciclo 20:00–19:59")

        // Changing 24h schedule to 22:00 -> 08:00 clips the 20:30-22:00 portion out of the active cycle
        let shiftedConfig = SleepScheduleConfiguration(
            nightStartHour: 22,
            nightStartMinute: 0,
            dayStartHour: 8,
            dayStartMinute: 0
        )
        try service.applyScheduleConfiguration(shiftedConfig, calendar: calendar)

        // Simulate a separate widget process reading from the same shared UserDefaults
        let widgetConfigManager = SleepConfigurationManager(userDefaults: configDefaults)
        let updatedSnapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: widgetConfigManager,
            now: now,
            calendar: calendar
        )
        // Night sleep clipped to [Nov 21 22:00, Nov 22 07:30] = 9h 30m + 1h 30m nap = 11h 0m
        XCTAssertEqual(updatedSnapshot.cycleTotalSleepDuration, 11.0 * 3600, accuracy: 1.0)
        XCTAssertEqual(updatedSnapshot.formattedCycleTotalSleep, "11h 0m")
        XCTAssertEqual(updatedSnapshot.formattedCycleWindow(calendar: calendar), "Ciclo 22:00–21:59")
    }

    func testDynamicBabyNameSyncsAcrossProcessesAndFallsBackToAppNameOnReset() {
        let now = makeDate(year: 2026, month: 11, day: 22, hour: 10, minute: 0)

        // Simulate separate widget process with its own standard UserDefaults + shared group UserDefaults
        let widgetStandardSuite = "test_widget_ext_std_\(UUID().uuidString)"
        let widgetStandardDefaults = UserDefaults(suiteName: widgetStandardSuite)!
        defer { widgetStandardDefaults.removePersistentDomain(forName: widgetStandardSuite) }

        // Pre-populate stale value in widget's own standard defaults (simulating legacy cached value)
        widgetStandardDefaults.set("NombreViejo", forKey: BabyProfileManager.babyNameKey)
        let widgetProfileManager = BabyProfileManager(defaults: widgetStandardDefaults, groupDefaults: groupProfileDefaults)

        // App sets baby name -> widget reads fresh value from shared group defaults
        profileManager.setBabyName("Sofía")
        let namedSnapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: widgetProfileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(namedSnapshot.displayName, "Sofía")

        // App updates baby name -> widget immediately reflects new name
        profileManager.setBabyName("Mateo")
        let renamedSnapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: widgetProfileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(renamedSnapshot.displayName, "Mateo")

        // App resets baby name to nil -> widget falls back to app name (ignoring stale widget standard defaults)
        profileManager.setBabyName(nil)
        let resetSnapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: widgetProfileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(resetSnapshot.displayName, BabyProfileManager.defaultAppName)
    }

    func testNextRefreshDateRespectsCycleRolloverBoundary() {
        let config = SleepScheduleConfiguration.standard // 19:00 -> 07:00
        configManager.save(config)

        // 5 minutes before cycle ends at 19:00 -> refresh right at 19:00
        let beforeRollover = makeDate(year: 2026, month: 11, day: 22, hour: 18, minute: 55)
        let snapshotNearBoundary = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: beforeRollover,
            calendar: calendar
        )
        let expectedRollover = makeDate(year: 2026, month: 11, day: 22, hour: 19, minute: 0)
        XCTAssertEqual(snapshotNearBoundary.nextRefreshDate(calendar: calendar), expectedRollover)

        // Mid-afternoon -> regular 15-minute refresh
        let midAfternoon = makeDate(year: 2026, month: 11, day: 22, hour: 15, minute: 0)
        let snapshotMidDay = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: midAfternoon,
            calendar: calendar
        )
        XCTAssertEqual(
            snapshotMidDay.nextRefreshDate(calendar: calendar),
            makeDate(year: 2026, month: 11, day: 22, hour: 15, minute: 15)
        )
    }

    func testWidgetDeepLinkTargetsHistoryView() {
        XCTAssertEqual(MediumWidgetSnapshot.widgetURL.scheme, "babysleeptracker")
        XCTAssertEqual(MediumWidgetSnapshot.widgetURL.host, "history")
    }

    func testReactiveReflectsEventEditsAndDeletions() throws {
        let sleepTime = makeDate(year: 2026, month: 11, day: 22, hour: 10, minute: 0)
        let wakeTime = makeDate(year: 2026, month: 11, day: 22, hour: 11, minute: 0)
        let now = makeDate(year: 2026, month: 11, day: 22, hour: 12, minute: 0)

        try service.recordEvent(type: .sleep, timestamp: sleepTime, force: true)
        var wakeEvent = try service.recordEvent(type: .wake, timestamp: wakeTime, force: true)

        var snapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.formattedLastEventTime(calendar: calendar), "11:00")
        XCTAssertEqual(snapshot.formattedCycleTotalSleep, "1h 0m")

        // Edit wake event to 11:30 -> snapshot reflects updated last event and 1h 30m total
        wakeEvent.timestamp = makeDate(year: 2026, month: 11, day: 22, hour: 11, minute: 30)
        try service.updateEvent(wakeEvent)

        snapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.formattedLastEventTime(calendar: calendar), "11:30")
        XCTAssertEqual(snapshot.formattedCycleTotalSleep, "1h 30m")

        // Delete wake event -> state returns to sleeping and action switches to "Se despertó"
        try service.deleteEvent(id: wakeEvent.id)

        snapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(snapshot.isSleeping)
        XCTAssertEqual(snapshot.primaryAction, .recordWake)
        XCTAssertEqual(snapshot.formattedLastEventTime(calendar: calendar), "10:00")
        XCTAssertEqual(snapshot.formattedCycleTotalSleep, "0m")
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: 0))!
    }
}
