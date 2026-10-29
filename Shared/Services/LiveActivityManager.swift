import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

public final class LiveActivityManager: @unchecked Sendable {
    public static let shared = LiveActivityManager()

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
        return Activity<SleepActivityAttributes>.activities.contains { $0.activityState == .active }
        #else
        return false
        #endif
    }

    @discardableResult
    public func syncWithCurrentState() async -> Bool {
        #if canImport(ActivityKit) && os(iOS)
        guard areActivitiesSupported else {
            return false
        }

        let service = SleepTrackingService.shared
        guard let state = try? service.getCurrentState() else {
            return false
        }

        // Notch / Dynamic Island is ONLY active when sleeping.
        // If awake or unknown, dismiss all live activities immediately.
        guard state.isSleeping, let sinceDate = state.sinceDate else {
            await stopAllActivities()
            return false
        }

        let contentState = SleepActivityAttributes.ContentState(
            isSleeping: true,
            startDate: sinceDate,
            statusTitle: "Durmiendo",
            babyName: "Emanuel"
        )
        let content = ActivityContent(state: contentState, staleDate: nil)

        let activeActivities = Activity<SleepActivityAttributes>.activities.filter { $0.activityState == .active }

        if let primary = activeActivities.first {
            await primary.update(content)

            // Dismiss any duplicate activities
            if activeActivities.count > 1 {
                for duplicate in activeActivities.dropFirst() {
                    await duplicate.end(nil, dismissalPolicy: .immediate)
                }
            }
            return true
        } else {
            let attributes = SleepActivityAttributes(babyName: "Emanuel")
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
