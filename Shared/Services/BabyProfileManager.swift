import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

public final class BabyProfileManager: ObservableObject {
    public static let shared = BabyProfileManager()

    public static let defaultAppName = "Baby Sleep Tracker"
    public static let babyNameKey = "com.samiro.babysleeptracker.babyName"
    public static let hasPromptedBabyNameKey = "com.samiro.babysleeptracker.hasPromptedBabyName"
    private static let babyNameSyncedToGroupKey = "com.samiro.babysleeptracker.babyNameSyncedToGroup"

    private let primaryDefaults: UserDefaults
    private let groupDefaults: UserDefaults?
    private let usesSharedStorage: Bool

    @Published public private(set) var babyName: String?
    @Published public private(set) var displayName: String
    @Published public private(set) var hasPromptedBabyName: Bool

    public init(defaults: UserDefaults? = nil, groupDefaults: UserDefaults? = nil) {
        if let defaults = defaults {
            self.primaryDefaults = defaults
            self.groupDefaults = groupDefaults
            self.usesSharedStorage = false
        } else {
            self.primaryDefaults = .standard
            // Only attach group suite if the container is genuinely accessible to avoid silent sandbox rejects
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupCoordinator.appGroupId) != nil {
                self.groupDefaults = UserDefaults(suiteName: AppGroupCoordinator.appGroupId)
            } else {
                self.groupDefaults = nil
            }
            self.usesSharedStorage = true
        }

        let loadedName = Self.readBabyName(primary: self.primaryDefaults, group: self.groupDefaults)
        self.babyName = loadedName
        self.displayName = loadedName ?? Self.defaultAppName
        self.hasPromptedBabyName = Self.readHasPrompted(primary: self.primaryDefaults, group: self.groupDefaults)
    }

    /// Reads the latest display name directly from shared storage without requiring main-thread publishing.
    /// Safe to call from WidgetKit timelines and AppIntents running in extension processes.
    public func currentDisplayName() -> String {
        Self.readBabyName(primary: primaryDefaults, group: groupDefaults) ?? Self.defaultAppName
    }

    private static func readBabyName(primary: UserDefaults, group: UserDefaults?) -> String? {
        if let group = group {
            if let name = group.string(forKey: babyNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            if group.bool(forKey: babyNameSyncedToGroupKey) {
                return nil
            }
        }
        if let name = primary.string(forKey: babyNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return nil
    }

    private static func readHasPrompted(primary: UserDefaults, group: UserDefaults?) -> Bool {
        if primary.bool(forKey: hasPromptedBabyNameKey) {
            return true
        }
        if let group = group, group.bool(forKey: hasPromptedBabyNameKey) {
            primary.set(true, forKey: hasPromptedBabyNameKey)
            primary.synchronize()
            return true
        }
        return false
    }

    /// Reloads current values from persistent storage.
    public func reloadFromDefaults() {
        let loadedName = Self.readBabyName(primary: self.primaryDefaults, group: self.groupDefaults)
        let loadedPrompted = Self.readHasPrompted(primary: self.primaryDefaults, group: self.groupDefaults)

        let updateBlock = {
            self.babyName = loadedName
            self.displayName = loadedName ?? Self.defaultAppName
            self.hasPromptedBabyName = loadedPrompted
            NotificationCenter.default.post(name: .babyProfileDidChange, object: self)
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.sync {
                updateBlock()
            }
        }
    }

    /// Updates the baby's name. If nil or empty string is passed, it clears the custom name,
    /// causing displayName to fall back to the default app name.
    public func setBabyName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmed != nil && !trimmed!.isEmpty) ? trimmed : nil

        if let validName = finalName {
            primaryDefaults.set(validName, forKey: Self.babyNameKey)
            groupDefaults?.set(validName, forKey: Self.babyNameKey)
        } else {
            primaryDefaults.removeObject(forKey: Self.babyNameKey)
            groupDefaults?.removeObject(forKey: Self.babyNameKey)
        }
        groupDefaults?.set(true, forKey: Self.babyNameSyncedToGroupKey)
        primaryDefaults.synchronize()
        groupDefaults?.synchronize()

        if usesSharedStorage {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }

        let updateBlock = {
            self.babyName = finalName
            self.displayName = finalName ?? Self.defaultAppName
            NotificationCenter.default.post(name: .babyProfileDidChange, object: self)
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.sync {
                updateBlock()
            }
        }
    }

    /// Marks the first-launch prompt as completed and optionally configures the baby's name.
    public func completeOnboarding(withBabyName name: String?) {
        self.hasPromptedBabyName = true
        primaryDefaults.set(true, forKey: Self.hasPromptedBabyNameKey)
        groupDefaults?.set(true, forKey: Self.hasPromptedBabyNameKey)
        primaryDefaults.synchronize()
        groupDefaults?.synchronize()

        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setBabyName(name)
        } else if self.babyName == nil {
            setBabyName(nil)
        }
    }

    /// Clears stored values for testing purposes.
    public func resetForTesting() {
        primaryDefaults.removeObject(forKey: Self.babyNameKey)
        primaryDefaults.removeObject(forKey: Self.hasPromptedBabyNameKey)
        groupDefaults?.removeObject(forKey: Self.babyNameKey)
        groupDefaults?.removeObject(forKey: Self.hasPromptedBabyNameKey)
        primaryDefaults.synchronize()
        groupDefaults?.synchronize()

        self.babyName = nil
        self.displayName = Self.defaultAppName
        self.hasPromptedBabyName = false

        NotificationCenter.default.post(name: .babyProfileDidChange, object: self)
    }
}

public extension Notification.Name {
    static let babyProfileDidChange = Notification.Name("com.samiro.babysleeptracker.babyProfileDidChange")
}
