import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public extension Notification.Name {
    static let sleepConfigurationDidChange = Notification.Name("com.samiro.babysleeptracker.configurationChanged")
}

public final class SleepConfigurationManager: @unchecked Sendable {
    public static let shared = SleepConfigurationManager()

    private let userDefaults: UserDefaults
    private let configKey = "baby_sleep_schedule_configuration"

    private let lock = NSLock()
    private var cachedConfiguration: SleepScheduleConfiguration?

    public init(userDefaults: UserDefaults? = nil) {
        if let userDefaults = userDefaults {
            self.userDefaults = userDefaults
        } else if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupCoordinator.appGroupId) != nil,
                  let suite = UserDefaults(suiteName: AppGroupCoordinator.appGroupId) {
            self.userDefaults = suite
        } else {
            self.userDefaults = .standard
        }
    }

    public var configuration: SleepScheduleConfiguration {
        get {
            lock.lock()
            defer { lock.unlock() }

            if let data = userDefaults.data(forKey: configKey),
               let decoded = try? JSONDecoder().decode(SleepScheduleConfiguration.self, from: data) {
                cachedConfiguration = decoded
                return decoded
            }

            let defaultConfig = SleepScheduleConfiguration.standard
            cachedConfiguration = defaultConfig
            return defaultConfig
        }
        set {
            save(newValue)
        }
    }

    public func save(_ newConfig: SleepScheduleConfiguration) {
        lock.lock()
        cachedConfiguration = newConfig
        if let encoded = try? JSONEncoder().encode(newConfig) {
            userDefaults.set(encoded, forKey: configKey)
        }
        lock.unlock()

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sleepConfigurationDidChange, object: nil)
            NotificationCenter.default.post(name: .sleepEventsDidChange, object: nil)
        }
    }

    public func resetToDefaults() {
        save(SleepScheduleConfiguration.standard)
    }

    /// Reclassifies all past sleep events that have `.unspecified` classification according to the current schedule.
    /// Returns the number of events updated.
    @discardableResult
    public func reclassifyUnspecifiedEvents(database: SQLiteDatabase) throws -> Int {
        let currentConfig = configuration
        return try database.performTransaction {
            let allEvents = try database.fetchAllEvents(ascending: true)
            var count = 0

            for event in allEvents where event.type == .sleep && event.classification == .unspecified {
                let suggested = currentConfig.classify(timestamp: event.timestamp)
                var updatedEvent = event
                updatedEvent.classification = suggested
                updatedEvent.updatedAt = Date()
                try database.updateEvent(updatedEvent)
                count += 1
            }

            if count > 0 {
                SleepTrackingService.shared.notifyDataChanged()
            }
            return count
        }
    }
}
