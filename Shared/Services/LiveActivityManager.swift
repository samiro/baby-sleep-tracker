import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

public final class LiveActivityManager: @unchecked Sendable {
    public static let shared = LiveActivityManager()

    private actor SyncCoordinator {
        private var activeTask: Task<Bool, Never>?

        func run(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
            if let previous = activeTask {
                _ = await previous.value
            }
            let task = Task {
                await operation()
            }
            activeTask = task
            let result = await task.value
            if activeTask == task {
                activeTask = nil
            }
            return result
        }
    }

    private let syncCoordinator = SyncCoordinator()

    private init() {}

    public var areActivitiesSupported: Bool {
        #if canImport(ActivityKit) && os(iOS)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    public var hasActiveActivity: Bool {
        #if canImport(ActivityKit) && os(iOS)
        return Activity<SleepActivityAttributes>.activities.contains {
            $0.activityState == .active || $0.activityState == .stale
        }
        #else
        return false
        #endif
    }

    #if canImport(ActivityKit)
    public static func makeContentState(
        for state: CurrentSleepState,
        babyName: String,
        fallbackDate: Date = Date()
    ) -> SleepActivityAttributes.ContentState {
        switch state {
        case .sleeping(let since, _):
            return SleepActivityAttributes.ContentState(
                isSleeping: true,
                startDate: since,
                statusTitle: "Durmiendo",
                babyName: babyName,
                hasStartDate: true
            )
        case .awake(let since, _):
            return SleepActivityAttributes.ContentState(
                isSleeping: false,
                startDate: since,
                statusTitle: "Despierto",
                babyName: babyName,
                hasStartDate: true
            )
        case .unknown:
            return SleepActivityAttributes.ContentState(
                isSleeping: false,
                startDate: fallbackDate,
                statusTitle: "Despierto",
                babyName: babyName,
                hasStartDate: false
            )
        }
    }
    #endif

    @discardableResult
    public func syncWithCurrentState() async -> Bool {
        return await syncCoordinator.run { [self] in
            await self.performSyncWithCurrentState()
        }
    }

    private func performSyncWithCurrentState() async -> Bool {
        #if canImport(ActivityKit) && os(iOS)
        guard areActivitiesSupported else {
            return false
        }

        let service = SleepTrackingService.shared
        let state = (try? service.getCurrentState()) ?? .unknown
        let babyName = BabyProfileManager.shared.displayName
        let contentState = Self.makeContentState(for: state, babyName: babyName)
        let content = ActivityContent(state: contentState, staleDate: nil)

        let allActivities = Activity<SleepActivityAttributes>.activities
        let updatableActivities = allActivities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }

        if let primary = updatableActivities.first {
            await primary.update(content)

            // Dismiss any duplicate or ended activities so only one widget remains visible
            for extra in allActivities where extra.id != primary.id {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return true
        } else {
            // Clear any ended/dismissed remnants before requesting a fresh activity
            for stale in allActivities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }

            let attributes = SleepActivityAttributes(babyName: babyName)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                return true
            } catch {
                print("[LiveActivityManager] Request error: \(error)")
                return false
            }
        }
        #else
        return false
        #endif
    }

    public func stopAllActivities() async {
        #if canImport(ActivityKit) && os(iOS)
        for activity in Activity<SleepActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}
