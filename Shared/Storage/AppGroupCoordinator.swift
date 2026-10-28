import Foundation

public final class AppGroupCoordinator: Sendable {
    public static let shared = AppGroupCoordinator()
    public static let appGroupId = "group.com.samiro.babysleeptracker"
    public static let databaseFilename = "emanuel_sleep.sqlite3"

    private init() {}

    public func databaseURL(overrideDirectory: URL? = nil) -> URL {
        if let overrideDirectory = overrideDirectory {
            return overrideDirectory.appendingPathComponent(Self.databaseFilename)
        }

        // Try App Group container first
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) {
            try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
            return containerURL.appendingPathComponent(Self.databaseFilename)
        }

        // Fallback for Simulator/Unit Tests without provisioned App Group
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("EmanuelSleepTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent(Self.databaseFilename)
    }
}
