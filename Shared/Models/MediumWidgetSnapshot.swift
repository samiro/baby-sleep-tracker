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

    public let date: Date
    public let displayName: String
    public let state: CurrentSleepState
    public let lastEvent: SleepEvent?
    public let cycleTotalSleepDuration: TimeInterval
    public let cycleRange: SleepCycleRange

    public init(
        date: Date,
        displayName: String,
        state: CurrentSleepState,
        lastEvent: SleepEvent?,
        cycleTotalSleepDuration: TimeInterval,
        cycleRange: SleepCycleRange
    ) {
        self.date = date
        self.displayName = displayName
        self.state = state
        self.lastEvent = lastEvent
        self.cycleTotalSleepDuration = max(0, cycleTotalSleepDuration)
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

    public var formattedCycleTotalSleep: String {
        DayMetrics.formatDuration(cycleTotalSleepDuration)
    }

    public func formattedLastEventTime(calendar: Calendar = .current) -> String? {
        guard let lastEvent else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: lastEvent.timestamp)
    }

    public var lastEventLabel: String? {
        guard let lastEvent else { return nil }
        switch lastEvent.type {
        case .sleep:
            return "Se durmió"
        case .wake:
            return "Se despertó"
        case .bedtimeRoutineStart, .sleepAttempt:
            return lastEvent.type.displayName
        }
    }

    public func formattedCycleWindow(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let startStr = formatter.string(from: cycleRange.start)
        let endStr = formatter.string(from: cycleRange.displayEnd)
        return "Ciclo \(startStr)–\(endStr)"
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
        let config = configurationManager.configuration
        let cycle = config.cycleRange(containing: now, calendar: calendar)
        let state = (try? service.getCurrentState()) ?? .unknown
        let lastEvent: SleepEvent?
        switch state {
        case .sleeping(_, let event):
            lastEvent = event
        case .awake(_, let event):
            lastEvent = event
        case .unknown:
            lastEvent = nil
        }

        let metrics = try? service.calculateCycleMetrics(
            for: cycle,
            calendar: calendar,
            configuration: config,
            now: now
        )

        return MediumWidgetSnapshot(
            date: now,
            displayName: profileManager.currentDisplayName(),
            state: state,
            lastEvent: lastEvent,
            cycleTotalSleepDuration: metrics?.totalSleepDuration ?? 0,
            cycleRange: cycle
        )
    }

    public static func placeholder(now: Date = Date(), calendar: Calendar = .current) -> MediumWidgetSnapshot {
        let sleepStart = now.addingTimeInterval(-1800)
        let event = SleepEvent(type: .sleep, timestamp: sleepStart)
        let cycle = SleepScheduleConfiguration.standard.cycleRange(containing: now, calendar: calendar)
        return MediumWidgetSnapshot(
            date: now,
            displayName: BabyProfileManager.defaultAppName,
            state: .sleeping(since: sleepStart, event: event),
            lastEvent: event,
            cycleTotalSleepDuration: 10.5 * 3600,
            cycleRange: cycle
        )
    }
}
