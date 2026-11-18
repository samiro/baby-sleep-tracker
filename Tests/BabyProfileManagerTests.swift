import XCTest
@testable import BabySleepTracker

final class BabyProfileManagerTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test_baby_profile_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    func testDefaultDisplayNameIsBabySleepTrackerWhenNoNameConfigured() {
        let manager = BabyProfileManager(defaults: testDefaults)

        XCTAssertNil(manager.babyName)
        XCTAssertFalse(manager.hasPromptedBabyName)
        XCTAssertEqual(manager.displayName, "Baby Sleep Tracker")
    }

    func testConfiguringBabyNameUpdatesDisplayNameAndPersists() {
        let manager = BabyProfileManager(defaults: testDefaults)

        manager.setBabyName("Emanuel")

        XCTAssertEqual(manager.babyName, "Emanuel")
        XCTAssertEqual(manager.displayName, "Emanuel")

        // Verify fresh manager reading from same defaults also gets the updated name
        let reloadedManager = BabyProfileManager(defaults: testDefaults)
        XCTAssertEqual(reloadedManager.babyName, "Emanuel")
        XCTAssertEqual(reloadedManager.displayName, "Emanuel")
    }

    func testTrimmingWhitespaceAndEmptyNameFallback() {
        let manager = BabyProfileManager(defaults: testDefaults)

        manager.setBabyName("   Sofía   ")
        XCTAssertEqual(manager.babyName, "Sofía")
        XCTAssertEqual(manager.displayName, "Sofía")

        manager.setBabyName("   ")
        XCTAssertNil(manager.babyName)
        XCTAssertEqual(manager.displayName, "Baby Sleep Tracker")

        manager.setBabyName("")
        XCTAssertNil(manager.babyName)
        XCTAssertEqual(manager.displayName, "Baby Sleep Tracker")
    }

    func testFirstLaunchPromptCompletionWithName() {
        let manager = BabyProfileManager(defaults: testDefaults)

        XCTAssertFalse(manager.hasPromptedBabyName)

        manager.completeOnboarding(withBabyName: "Lucas")

        XCTAssertTrue(manager.hasPromptedBabyName)
        XCTAssertEqual(manager.babyName, "Lucas")
        XCTAssertEqual(manager.displayName, "Lucas")
    }

    func testFirstLaunchPromptCompletionWithoutNameDefaultsToAppName() {
        let manager = BabyProfileManager(defaults: testDefaults)

        XCTAssertFalse(manager.hasPromptedBabyName)

        manager.completeOnboarding(withBabyName: nil)

        XCTAssertTrue(manager.hasPromptedBabyName)
        XCTAssertNil(manager.babyName)
        XCTAssertEqual(manager.displayName, "Baby Sleep Tracker")
    }

    func testEditingNameFromSettingsAndResettingToDefault() {
        let manager = BabyProfileManager(defaults: testDefaults)

        // Initial setup
        manager.completeOnboarding(withBabyName: "Camila")
        XCTAssertEqual(manager.displayName, "Camila")

        // Edit from settings
        manager.setBabyName("Camila Paz")
        XCTAssertEqual(manager.displayName, "Camila Paz")

        // Reset to default from settings
        manager.setBabyName(nil)
        XCTAssertNil(manager.babyName)
        XCTAssertEqual(manager.displayName, "Baby Sleep Tracker")
    }

    func testNotificationPostedOnBabyNameChange() {
        let manager = BabyProfileManager(defaults: testDefaults)
        let expectation = expectation(description: "babyProfileDidChange notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .babyProfileDidChange,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        manager.setBabyName("Oliver")

        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
