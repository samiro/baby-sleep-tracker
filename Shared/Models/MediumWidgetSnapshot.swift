import Foundation

/// Single primary action displayed on the 4x2 Home Screen widget, switching dynamically with the baby's state.
public enum MediumWidgetAction: Equatable, Sendable {
    case recordSleep
    case recordWake

    public var title: String {
        switch self {
        case .recordSleep:
            return "Se durmió"
        case .recordWake:
            return "Se despertó"
        }
    }

    public var iconName: String {
        switch self {
        case .recordSleep:
            return "moon.fill"
        case .recordWake:
            return "sun.max.fill"
        }
    }
}

/// Concise, non-redundant view data for the 4x2 Home Screen widget, aligned with global profile and 24-hour cycle settings.
public struct MediumWidgetSnapshot: Equatable, Sendable {
    public static let widgetURL = URL(string: "babysleeptracker://history")!
    public static let nightSleepIconName = SleepClassification.nightSleep.iconName
    public static let daytimeSleepIconName = SleepClassification.nap.iconName

    public let date: Date
    public let displayName: String
    public let state: CurrentSleepState
    /// Up to the last 2 events recorded inside `cycleRange`, ordered most-recent first.
    public let recentCycleEvents: [SleepEvent]
    /// Total nighttime sleep in `cycleRange` at `date` (including active ongoing night sleep).
    public let cycleNightSleepDuration: TimeInterval
    /// Total daytime sleep in `cycleRange` at `date` (including active ongoing daytime sleep).
    public let cycleDaytimeSleepDuration: TimeInterval
    public let cycleRange: SleepCycleRange

    public init(
        date: Date,
        displayName: String,
        state: CurrentSleepState,
        recentCycleEvents: [SleepEvent],
        cycleNightSleepDuration: TimeInterval,
        cycleDaytimeSleepDuration: TimeInterval,
        cycleRange: SleepCycleRange
    ) {
        self.date = date
        self.displayName = displayName
        self.state = state
        self.recentCycleEvents = Array(recentCycleEvents.prefix(2))
        self.cycleNightSleepDuration = max(0, cycleNightSleepDuration)
        self.cycleDaytimeSleepDuration = max(0, cycleDaytimeSleepDuration)
        self.cycleRange = cycleRange
    }

    public var isSleeping: Bool {
        state.isSleeping
    }

    public var stateTitle: String {
        switch state {
        case .sleeping:
            return "Durmiendo"
        case .awake:
            return "Despierto"
        case .unknown:
            return "Sin registro"
        }
    }

    public var stateIconName: String {
        switch state {
        case .sleeping:
            return "moon.stars.fill"
        case .awake:
            return "sun.max.fill"
        case .unknown:
            return "moon.zzz.fill"
        }
    }

    public var primaryAction: MediumWidgetAction {
        isSleeping ? .recordWake : .recordSleep
    }

    public var lastEvent: SleepEvent? {
        recentCycleEvents.first
    }

    public var cycleTotalSleepDuration: TimeInterval {
        cycleNightSleepDuration + cycleDaytimeSleepDuration
    }

    public var formattedCycleNightSleep: String {
        Self.formatCompactDuration(cycleNightSleepDuration)
    }

    public var formattedCycleDaytimeSleep: String {
        Self.formatCompactDuration(cycleDaytimeSleepDuration)
    }

    public var formattedCycleTotalSleep: String {
        Self.formatCompactDuration(cycleTotalSleepDuration)
    }

    public static func formatCompactDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return "\(minutes)m"
        }
    }

    public static func formattedTime(for event: SleepEvent, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.timestamp)
    }

    public static func eventLabel(for event: SleepEvent) -> String {
        switch event.type {
        case .sleep:
            return "Se durmió"
        case .wake:
            return "Se despertó"
        case .bedtimeRoutineStart, .sleepAttempt:
            return event.type.displayName
        }
    }

    public func formattedLastEventTime(calendar: Calendar = .current) -> String? {
        lastEvent.map { Self.formattedTime(for: $0, calendar: calendar) }
    }

    public var lastEventLabel: String? {
        lastEvent.map { Self.eventLabel(for: $0) }
    }

    /// Computes the next timeline refresh date: at most 15 minutes from `date`,
    /// or right when the active 24-hour cycle ends if that comes sooner.
    public func nextRefreshDate(calendar: Calendar = .current) -> Date {
        let regularRefresh = calendar.date(byAdding: .minute, value: 15, to: date) ?? date.addingTimeInterval(900)
        if cycleRange.end > date && cycleRange.end < regularRefresh {
            return cycleRange.end
        }
        return regularRefresh
    }

    public static func make(
        service: SleepTrackingService = .shared,
        profileManager: BabyProfileManager = .shared,
        configurationManager: SleepConfigurationManager = .shared,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MediumWidgetSnapshot {
        let context = loadContext(
            service: service,
            profileManager: profileManager,
            configurationManager: configurationManager,
            now: now,
            calendar: calendar
        )
        return snapshot(from: context, at: now)
    }

    /// Generates timeline snapshots for WidgetKit. When the baby is actively sleeping,
    /// emits minute-by-minute entries aligned to the exact minute rollovers of the active
    /// sleep counter (stopping before `cycleRange.end`) so night/day totals update in real time.
    public static func makeTimeline(
        service: SleepTrackingService = .shared,
        profileManager: BabyProfileManager = .shared,
        configurationManager: SleepConfigurationManager = .shared,
        now: Date = Date(),
        calendar: Calendar = .current,
        maxActiveMinuteEntries: Int = 60
    ) -> (snapshots: [MediumWidgetSnapshot], nextRefreshDate: Date) {
        let context = loadContext(
            service: service,
            profileManager: profileManager,
            configurationManager: configurationManager,
            now: now,
            calendar: calendar
        )
        let currentSnapshot = snapshot(from: context, at: now)

        guard let ongoing = context.ongoingInterval,
              maxActiveMinuteEntries > 0,
              now < context.cycle.end else {
            return ([currentSnapshot], currentSnapshot.nextRefreshDate(calendar: calendar))
        }

        let activeBucketDuration: TimeInterval
        switch ongoing.classification {
        case .nap:
            activeBucketDuration = currentSnapshot.cycleDaytimeSleepDuration
        case .nightSleep, .unspecified:
            activeBucketDuration = currentSnapshot.cycleNightSleepDuration
        }

        // Advance to the exact moment the displayed minute increments (+50ms safety margin against FP truncation).
        let currentWholeMinutes = floor(max(0, activeBucketDuration) / 60.0)
        let secondsToNextMinute = ((currentWholeMinutes + 1.0) * 60.0) - max(0, activeBucketDuration)
        let firstTickOffset = max(0.05, secondsToNextMinute) + 0.05
        var tickDate = now.addingTimeInterval(firstTickOffset)

        var snapshots = [currentSnapshot]
        var generatedTicks = 0

        while generatedTicks < maxActiveMinuteEntries && tickDate < context.cycle.end {
            snapshots.append(snapshot(from: context, at: tickDate))
            generatedTicks += 1
            tickDate = tickDate.addingTimeInterval(60.0)
        }

        let nextRefresh = min(tickDate, context.cycle.end)
        return (snapshots, nextRefresh)
    }

    public static func placeholder(now: Date = Date(), calendar: Calendar = .current) -> MediumWidgetSnapshot {
        let sleepStart = now.addingTimeInterval(-1800)
        let previousWake = now.addingTimeInterval(-9000)
        let sleepEvent = SleepEvent(type: .sleep, timestamp: sleepStart)
        let wakeEvent = SleepEvent(type: .wake, timestamp: previousWake)
        let cycle = SleepScheduleConfiguration.standard.cycleRange(containing: now, calendar: calendar)
        return MediumWidgetSnapshot(
            date: now,
            displayName: BabyProfileManager.defaultAppName,
            state: .sleeping(since: sleepStart, event: sleepEvent),
            recentCycleEvents: [sleepEvent, wakeEvent],
            cycleNightSleepDuration: 8.5 * 3600,
            cycleDaytimeSleepDuration: (2 * 3600) + (5 * 60),
            cycleRange: cycle
        )
    }

    // MARK: - Private Helpers

    private struct TimelineContext {
        let displayName: String
        let state: CurrentSleepState
        let recentCycleEvents: [SleepEvent]
        let metrics: DayMetrics?
        let ongoingInterval: SleepInterval?
        let cycle: SleepCycleRange
    }

    private static func loadContext(
        service: SleepTrackingService,
        profileManager: BabyProfileManager,
        configurationManager: SleepConfigurationManager,
        now: Date,
        calendar: Calendar
    ) -> TimelineContext {
        let config = configurationManager.configuration
        let cycle = config.cycleRange(containing: now, calendar: calendar)
        let state = (try? service.getCurrentState()) ?? .unknown

        let cycleEvents = (try? service.fetchEvents(in: cycle)) ?? []
        let sortedCycleEvents = cycleEvents.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let recentCycleEvents = Array(sortedCycleEvents.suffix(2).reversed())

        let metrics = try? service.calculateCycleMetrics(
            for: cycle,
            calendar: calendar,
            configuration: config,
            now: now
        )

        let ongoingInterval = try? service.activeSleepInterval(
            in: cycle,
            configuration: config,
            now: now,
            calendar: calendar
        )

        return TimelineContext(
            displayName: profileManager.currentDisplayName(),
            state: state,
            recentCycleEvents: recentCycleEvents,
            metrics: metrics,
            ongoingInterval: ongoingInterval,
            cycle: cycle
        )
    }

    private static func snapshot(from context: TimelineContext, at date: Date) -> MediumWidgetSnapshot {
        let nightDuration = context.metrics?.effectiveTotalNightSleepDuration(
            including: context.ongoingInterval,
            at: date
        ) ?? 0
        let daytimeDuration = context.metrics?.effectiveTotalDaytimeSleepDuration(
            including: context.ongoingInterval,
            at: date
        ) ?? 0

        return MediumWidgetSnapshot(
            date: date,
            displayName: context.displayName,
            state: context.state,
            recentCycleEvents: context.recentCycleEvents,
            cycleNightSleepDuration: nightDuration,
            cycleDaytimeSleepDuration: daytimeDuration,
            cycleRange: context.cycle
        )
    }
}
