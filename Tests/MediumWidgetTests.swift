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
        XCTAssertTrue(emptySnapshot.recentCycleEvents.isEmpty)
        XCTAssertEqual(emptySnapshot.formattedCycleNightSleep, "0m")
        XCTAssertEqual(emptySnapshot.formattedCycleDaytimeSleep, "0m")
        XCTAssertEqual(emptySnapshot.formattedCycleTotalSleep, "0m")

        // After recording daytime sleep -> single action switches to "Se despertó" and active sleep counts live
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
        XCTAssertEqual(sleepingSnapshot.recentCycleEvents.count, 1)
        XCTAssertEqual(sleepingSnapshot.lastEventLabel, "Se durmió")
        XCTAssertEqual(sleepingSnapshot.formattedLastEventTime(calendar: calendar), "13:30")
        XCTAssertEqual(sleepingSnapshot.cycleNightSleepDuration, 0, accuracy: 1.0)
        XCTAssertEqual(sleepingSnapshot.cycleDaytimeSleepDuration, 30 * 60, accuracy: 1.0)
        XCTAssertEqual(sleepingSnapshot.formattedCycleDaytimeSleep, "30m")

        // After recording wake -> single action switches back to "Se durmió", both events show, and daytime sleep updates
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
        XCTAssertEqual(awakeSnapshot.recentCycleEvents.count, 2)
        XCTAssertEqual(awakeSnapshot.lastEventLabel, "Se despertó")
        XCTAssertEqual(awakeSnapshot.formattedLastEventTime(calendar: calendar), "14:45")
        XCTAssertEqual(MediumWidgetSnapshot.formattedTime(for: awakeSnapshot.recentCycleEvents[1], calendar: calendar), "13:30")
        XCTAssertEqual(awakeSnapshot.cycleNightSleepDuration, 0, accuracy: 1.0)
        XCTAssertEqual(awakeSnapshot.cycleDaytimeSleepDuration, 75 * 60, accuracy: 1.0)
        XCTAssertEqual(awakeSnapshot.formattedCycleDaytimeSleep, "1h 15m")
        XCTAssertEqual(awakeSnapshot.formattedCycleTotalSleep, "1h 15m")
    }

    func testCycleNightAndDayBreakdownRespectsConfigured24HourCycleNotMidnight() throws {
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
        // Night sleep starting BEFORE midnight: Nov 21 20:30 -> Nov 22 07:30 (11h 00m)
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

        XCTAssertEqual(snapshot.cycleNightSleepDuration, 11.0 * 3600, accuracy: 1.0)
        XCTAssertEqual(snapshot.cycleDaytimeSleepDuration, 1.5 * 3600, accuracy: 1.0)
        XCTAssertEqual(snapshot.formattedCycleNightSleep, "11h 00m")
        XCTAssertEqual(snapshot.formattedCycleDaytimeSleep, "1h 30m")
        XCTAssertEqual(snapshot.formattedCycleTotalSleep, "12h 30m")

        // Changing 24h schedule to 22:00 -> 08:00 clips the 20:30-22:00 portion out of the active cycle
        // AND reclassifies the 20:30 start as daytime (08:00-22:00), leaving 0m night and 11h 00m day.
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
        XCTAssertEqual(updatedSnapshot.cycleNightSleepDuration, 0, accuracy: 1.0)
        XCTAssertEqual(updatedSnapshot.cycleDaytimeSleepDuration, 11.0 * 3600, accuracy: 1.0)
        XCTAssertEqual(updatedSnapshot.formattedCycleNightSleep, "0m")
        XCTAssertEqual(updatedSnapshot.formattedCycleDaytimeSleep, "11h 00m")
        XCTAssertEqual(updatedSnapshot.formattedCycleTotalSleep, "11h 00m")
    }

    func testActiveDaytimeSleepAddsInRealTimeToCompletedDaytimeTotal() throws {
        // Standard cycle: 19:00 -> 07:00
        configManager.save(.standard)

        // Completed night sleep: 22:00 -> 06:30 (8h 30m)
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 22, minute: 0), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 6, minute: 30), force: true)

        // Completed daytime nap: 10:00 -> 12:00 (2h 00m)
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 10, minute: 0), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 12, minute: 0), force: true)

        // Falls asleep again at 14:00 (daytime) and has been sleeping for 5 minutes at 14:05
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 14, minute: 0), force: true)

        let now = makeDate(year: 2026, month: 11, day: 22, hour: 14, minute: 5)
        let snapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )

        // Night stays 8h 30m; Day adds 5m active to 2h 00m completed -> 2h 05m
        XCTAssertEqual(snapshot.formattedCycleNightSleep, "8h 30m")
        XCTAssertEqual(snapshot.formattedCycleDaytimeSleep, "2h 05m")
        XCTAssertEqual(snapshot.cycleDaytimeSleepDuration, (2 * 3600) + (5 * 60), accuracy: 1.0)
    }

    func testActiveNighttimeSleepAddsInRealTimeToCompletedNighttimeTotal() throws {
        // Standard cycle: 19:00 -> 07:00
        configManager.save(.standard)

        // Completed night stretch: 20:00 -> 00:00 (4h 00m)
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 20, minute: 0), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 0, minute: 0), force: true)

        // Falls back asleep at 00:30 (nighttime) and has been sleeping for 45m at 01:15
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 0, minute: 30), force: true)

        let now = makeDate(year: 2026, month: 11, day: 22, hour: 1, minute: 15)
        let snapshot = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.formattedCycleNightSleep, "4h 45m")
        XCTAssertEqual(snapshot.formattedCycleDaytimeSleep, "0m")
    }

    func testMakeTimelineGeneratesMinuteByMinuteEntriesWhileSleepingAndStopsAtCycleEnd() throws {
        configManager.save(.standard) // 19:00 -> 07:00

        // 2h 00m completed daytime sleep
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 10, minute: 0), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 12, minute: 0), force: true)

        // Active nap started at 18:55:20; now is 18:56:50 (1m 30s elapsed -> 2h 01m, next rollover in 30s at 18:57:20)
        let sleepStart = makeDate(year: 2026, month: 11, day: 22, hour: 18, minute: 55, second: 20)
        try service.recordEvent(type: .sleep, timestamp: sleepStart, force: true)

        let now = makeDate(year: 2026, month: 11, day: 22, hour: 18, minute: 56, second: 50)
        let (snapshots, nextRefresh) = MediumWidgetSnapshot.makeTimeline(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar,
            maxActiveMinuteEntries: 10
        )

        // Entries expected:
        // 0: 18:56:50 -> 2h 01m
        // 1: 18:57:20 -> 2h 02m
        // 2: 18:58:20 -> 2h 03m
        // 3: 18:59:20 -> 2h 04m
        // Next tick (19:00:20) >= cycle end (19:00:00) -> stop and refresh at 19:00:00
        XCTAssertEqual(snapshots.count, 4)
        XCTAssertEqual(snapshots[0].formattedCycleDaytimeSleep, "2h 01m")
        XCTAssertEqual(snapshots[1].formattedCycleDaytimeSleep, "2h 02m")
        XCTAssertEqual(snapshots[2].formattedCycleDaytimeSleep, "2h 03m")
        XCTAssertEqual(snapshots[3].formattedCycleDaytimeSleep, "2h 04m")
        XCTAssertEqual(nextRefresh, makeDate(year: 2026, month: 11, day: 22, hour: 19, minute: 0))
    }

    func testRecentCycleEventsShowsZeroOneOrLastTwoEventsStrictlyWithinCurrentCycle() throws {
        configManager.save(.standard) // 19:00 -> 07:00
        let now = makeDate(year: 2026, month: 11, day: 22, hour: 16, minute: 0)

        // Event in PREVIOUS cycle (Nov 21 18:00) -> current cycle still has 0 events
        try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 18, minute: 0), force: true)
        try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 18, minute: 45), force: true)

        let zeroInCycle = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(zeroInCycle.recentCycleEvents.isEmpty)

        // 1 event in current cycle -> shows only that 1 event (does NOT backfill from previous cycle)
        let e1 = try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 21, hour: 20, minute: 30), force: true)
        let oneInCycle = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(oneInCycle.recentCycleEvents.map(\.id), [e1.id])
        XCTAssertEqual(MediumWidgetSnapshot.formattedTime(for: oneInCycle.recentCycleEvents[0], calendar: calendar), "20:30")

        // 2 events in current cycle -> shows both, most recent first
        let e2 = try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 7, minute: 0), force: true)
        let twoInCycle = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(twoInCycle.recentCycleEvents.map(\.id), [e2.id, e1.id])

        // 4 events in current cycle -> shows ONLY the last 2, most recent first
        let e3 = try service.recordEvent(type: .sleep, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 10, minute: 15), force: true)
        let e4 = try service.recordEvent(type: .wake, timestamp: makeDate(year: 2026, month: 11, day: 22, hour: 11, minute: 45), force: true)
        let fourInCycle = MediumWidgetSnapshot.make(
            service: service,
            profileManager: profileManager,
            configurationManager: configManager,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(fourInCycle.recentCycleEvents.map(\.id), [e4.id, e3.id])
        XCTAssertEqual(MediumWidgetSnapshot.formattedTime(for: fourInCycle.recentCycleEvents[0], calendar: calendar), "11:45")
        XCTAssertEqual(MediumWidgetSnapshot.eventLabel(for: fourInCycle.recentCycleEvents[0]), "Se despertó")
        XCTAssertEqual(MediumWidgetSnapshot.formattedTime(for: fourInCycle.recentCycleEvents[1], calendar: calendar), "10:15")
        XCTAssertEqual(MediumWidgetSnapshot.eventLabel(for: fourInCycle.recentCycleEvents[1]), "Se durmió")
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
        XCTAssertEqual(snapshot.formattedCycleDaytimeSleep, "1h 00m")

        // Edit wake event to 11:30 -> snapshot reflects updated last event and 1h 30m daytime total
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
        XCTAssertEqual(snapshot.formattedCycleDaytimeSleep, "1h 30m")

        // Delete wake event -> state returns to sleeping, action switches to "Se despertó",
        // and active sleep since 10:00 counts live as 2h 00m at 12:00
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
        XCTAssertEqual(snapshot.recentCycleEvents.count, 1)
        XCTAssertEqual(snapshot.formattedLastEventTime(calendar: calendar), "10:00")
        XCTAssertEqual(snapshot.formattedCycleDaytimeSleep, "2h 00m")
        XCTAssertEqual(snapshot.formattedCycleNightSleep, "0m")
    }

    func testCompactDurationFormatting() {
        XCTAssertEqual(MediumWidgetSnapshot.formatCompactDuration(0), "0m")
        XCTAssertEqual(MediumWidgetSnapshot.formatCompactDuration(5 * 60), "5m")
        XCTAssertEqual(MediumWidgetSnapshot.formatCompactDuration(59 * 60), "59m")
        XCTAssertEqual(MediumWidgetSnapshot.formatCompactDuration(2 * 3600), "2h 00m")
        XCTAssertEqual(MediumWidgetSnapshot.formatCompactDuration(2 * 3600 + 5 * 60), "2h 05m")
        XCTAssertEqual(MediumWidgetSnapshot.formatCompactDuration(8 * 3600 + 30 * 60), "8h 30m")
    }

    func testDaytimeSleepIconIsDistinctFromAwakeSunIcon() {
        XCTAssertEqual(MediumWidgetSnapshot.nightSleepIconName, SleepClassification.nightSleep.iconName)
        XCTAssertEqual(MediumWidgetSnapshot.daytimeSleepIconName, SleepClassification.nap.iconName)
        XCTAssertNotEqual(MediumWidgetSnapshot.daytimeSleepIconName, MediumWidgetAction.recordWake.iconName)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}
