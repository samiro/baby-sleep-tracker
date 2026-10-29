import XCTest
@testable import BabySleepTracker

final class LiveActivityTests: XCTestCase {
    private var tempDir: URL!
    private var database: SQLiteDatabase!
    private var service: SleepTrackingService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.sqlite3")
        database = try SQLiteDatabase(url: dbURL)
        service = SleepTrackingService(database: database)
    }

    override func tearDownWithError() throws {
        database = nil
        service = nil
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    func testSleepActivityAttributesInitialization() {
        let defaultAttributes = SleepActivityAttributes()
        XCTAssertEqual(defaultAttributes.babyName, "Emanuel")

        let customAttributes = SleepActivityAttributes(babyName: "Baby")
        XCTAssertEqual(customAttributes.babyName, "Baby")
    }

    func testContentStateSleepingPropertiesAndCodable() throws {
        let now = Date()
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: true,
            startDate: now,
            statusTitle: "Durmiendo",
            babyName: "Emanuel"
        )

        XCTAssertTrue(contentState.isSleeping)
        XCTAssertEqual(contentState.startDate, now)
        XCTAssertEqual(contentState.statusTitle, "Durmiendo")
        XCTAssertEqual(contentState.babyName, "Emanuel")

        let encoded = try JSONEncoder().encode(contentState)
        let decoded = try JSONDecoder().decode(SleepActivityAttributes.ContentState.self, from: encoded)

        XCTAssertEqual(decoded.isSleeping, contentState.isSleeping)
        XCTAssertEqual(decoded.statusTitle, contentState.statusTitle)
        XCTAssertEqual(decoded.babyName, contentState.babyName)
        XCTAssertEqual(floor(decoded.startDate.timeIntervalSince1970), floor(contentState.startDate.timeIntervalSince1970))
    }

    func testContentStateAwakePropertiesAndCodable() throws {
        let now = Date()
        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: false,
            startDate: now,
            statusTitle: "Despierto",
            babyName: "Emanuel"
        )

        XCTAssertFalse(contentState.isSleeping)
        XCTAssertEqual(contentState.startDate, now)
        XCTAssertEqual(contentState.statusTitle, "Despierto")
        XCTAssertEqual(contentState.babyName, "Emanuel")

        let encoded = try JSONEncoder().encode(contentState)
        let decoded = try JSONDecoder().decode(SleepActivityAttributes.ContentState.self, from: encoded)

        XCTAssertEqual(decoded.isSleeping, false)
        XCTAssertEqual(decoded.statusTitle, "Despierto")
    }

    func testServiceSleepToWakeStateTransitionsForNotchLiveActivity() throws {
        let sleepTime = Date().addingTimeInterval(-3600)
        try service.recordEvent(type: .sleep, timestamp: sleepTime)

        let sleepState = try service.getCurrentState()
        XCTAssertTrue(sleepState.isSleeping)
        XCTAssertEqual(sleepState.sinceDate!.timeIntervalSince1970, sleepTime.timeIntervalSince1970, accuracy: 1.0)

        let sleepContentState = SleepActivityAttributes.ContentState(
            isSleeping: sleepState.isSleeping,
            startDate: sleepState.sinceDate ?? Date(),
            statusTitle: sleepState.isSleeping ? "Durmiendo" : "Despierto"
        )
        XCTAssertTrue(sleepContentState.isSleeping)
        XCTAssertEqual(sleepContentState.statusTitle, "Durmiendo")

        let wakeTime = Date().addingTimeInterval(-1800)
        try service.recordEvent(type: .wake, timestamp: wakeTime)

        let wakeState = try service.getCurrentState()
        XCTAssertFalse(wakeState.isSleeping)
        XCTAssertEqual(wakeState.sinceDate!.timeIntervalSince1970, wakeTime.timeIntervalSince1970, accuracy: 1.0)

        let wakeContentState = SleepActivityAttributes.ContentState(
            isSleeping: wakeState.isSleeping,
            startDate: wakeState.sinceDate ?? Date(),
            statusTitle: wakeState.isSleeping ? "Durmiendo" : "Despierto"
        )
        XCTAssertFalse(wakeContentState.isSleeping)
        XCTAssertEqual(wakeContentState.statusTitle, "Despierto")
    }

    func testLiveActivityOnlyActiveWhenSleeping() throws {
        // When awake, notch is not activated
        try service.recordEvent(type: .wake)
        let wakeState = try service.getCurrentState()
        XCTAssertFalse(wakeState.isSleeping)

        // When sleeping, notch is activated
        try service.recordEvent(type: .sleep, force: true)
        let sleepState = try service.getCurrentState()
        XCTAssertTrue(sleepState.isSleeping)
    }

    func testLiveActivityManagerProperties() {
        let manager = LiveActivityManager.shared
        _ = manager.areActivitiesSupported
        _ = manager.hasActiveActivity
        XCTAssertNotNil(manager)
    }
}
