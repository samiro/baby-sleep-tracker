import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

public extension Notification.Name {
    static let sleepEventsDidChange = Notification.Name("com.samiro.babysleeptracker.eventsChanged")
}

public enum CurrentSleepState: Equatable, Sendable {
    case sleeping(since: Date, event: SleepEvent)
    case awake(since: Date, event: SleepEvent?)
    case unknown

    public var isSleeping: Bool {
        if case .sleeping = self { return true }
        return false
    }

    public var sinceDate: Date? {
        switch self {
        case .sleeping(let since, _): return since
        case .awake(let since, _): return since
        case .unknown: return nil
        }
    }
}

public enum SleepTrackingError: Error, LocalizedError, Equatable, Sendable {
    case alreadySleeping(Date)
    case alreadyAwake(Date)
    case invalidTimestamp(String)
    case storage(String)

    public var errorDescription: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        switch self {
        case .alreadySleeping(let date):
            return "\(BabyProfileManager.shared.displayName) ya figura durmiendo desde las \(formatter.string(from: date))."
        case .alreadyAwake(let date):
            return "\(BabyProfileManager.shared.displayName) ya figura despierto desde las \(formatter.string(from: date))."
        case .invalidTimestamp(let message):
            return "Fecha inválida: \(message)"
        case .storage(let message):
            return "Error de almacenamiento: \(message)"
        }
    }
}

public final class SleepTrackingService: @unchecked Sendable {
    public static let shared = SleepTrackingService()

    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase? = nil) {
        if let database = database {
            self.database = database
        } else {
            let dbURL = AppGroupCoordinator.shared.databaseURL()
            do {
                self.database = try SQLiteDatabase(url: dbURL)
            } catch {
                fatalError("Failed to initialize database at \(dbURL): \(error)")
            }
        }
    }

    // MARK: - Event Recording

    @discardableResult
    public func recordEvent(
        type: EventType,
        timestamp: Date = Date(),
        classification: SleepClassification = .unspecified,
        notes: String? = nil,
        force: Bool = false
    ) throws -> SleepEvent {
        return try database.performTransaction {
            let latest = try database.fetchLatestEvent()

            // Prevent accidental rapid double-taps within 5 seconds unless forced,
            // while allowing consecutive events of the same type without blocking.
            if !force, let latest = latest,
               (type == .sleep || type == .wake),
               type == latest.type,
               abs(timestamp.timeIntervalSince(latest.timestamp)) < 5 {
                return latest
            }

            var finalClassification = classification
            if finalClassification == .unspecified && type == .sleep {
                // Classify daytime vs night sleep based on configured schedule
                finalClassification = SleepConfigurationManager.shared.configuration.classify(timestamp: timestamp)
            }

            let newEvent = SleepEvent(
                id: UUID(),
                type: type,
                timestamp: timestamp,
                classification: finalClassification,
                notes: notes,
                createdAt: Date(),
                updatedAt: Date()
            )

            try database.insertEvent(newEvent)

            // Trigger widget reload & notify app
            notifyDataChanged()

            return newEvent
        }
    }

    public func updateEvent(_ event: SleepEvent) throws {
        try database.performTransaction {
            var updated = event
            updated.updatedAt = Date()
            try database.updateEvent(updated)
            notifyDataChanged()
        }
    }

    public func deleteEvent(id: UUID) throws {
        try database.performTransaction {
            try database.deleteEvent(id: id)
            notifyDataChanged()
        }
    }

    @discardableResult
    public func reclassifyUnspecifiedEvents() throws -> Int {
        return try SleepConfigurationManager.shared.reclassifyUnspecifiedEvents(database: database)
    }

    public func resetAllData() throws {
        try database.performTransaction {
            try database.deleteAllEvents()
            notifyDataChanged()
        }
    }

    public func notifyDataChanged() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        #if canImport(ActivityKit)
        Task {
            await LiveActivityManager.shared.syncWithCurrentState()
        }
        #endif
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sleepEventsDidChange, object: nil)
        }
    }

    // MARK: - State Inspection

    public func getCurrentState() throws -> CurrentSleepState {
        guard let latest = try database.fetchLatestEvent() else {
            return .unknown
        }

        switch latest.type {
        case .sleep:
            return .sleeping(since: latest.timestamp, event: latest)
        case .wake:
            return .awake(since: latest.timestamp, event: latest)
        case .bedtimeRoutineStart, .sleepAttempt:
            // Find most recent sleep or wake
            let events = try database.fetchAllEvents(ascending: false)
            for e in events {
                if e.type == .sleep {
                    return .sleeping(since: e.timestamp, event: e)
                } else if e.type == .wake {
                    return .awake(since: e.timestamp, event: e)
                }
            }
            return .awake(since: latest.timestamp, event: nil)
        }
    }

    public func getMostRecentSleepInterval() throws -> SleepInterval? {
        let events = try database.fetchAllEvents(ascending: true)
        let (sleepIntervals, _) = computeIntervals(from: events)
        return sleepIntervals.last
    }

    public func getMostRecentInterval() throws -> TrackedInterval? {
        let state = try getCurrentState()
        switch state {
        case .sleeping(_, let event):
            return .sleep(SleepInterval(startEvent: event, endEvent: nil))
        case .awake(_, let event):
            if let wakeEvent = event {
                return .awake(AwakeInterval(wakeEvent: wakeEvent, nextSleepEvent: nil))
            }
            return nil
        case .unknown:
            return nil
        }
    }

    public func fetchAllEvents(ascending: Bool = true) throws -> [SleepEvent] {
        return try database.fetchAllEvents(ascending: ascending)
    }

    public func fetchEvents(for date: Date, calendar: Calendar = .current) throws -> [SleepEvent] {
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        return try database.fetchEvents(from: startOfDay, to: endOfDay)
    }

    public func fetchIncompleteEventReasons() throws -> [UUID: SleepEventIncompleteReason] {
        let allEvents = try database.fetchAllEvents(ascending: true)
        return analyzeTimeline(from: allEvents).incompleteEventReasons
    }

    // MARK: - Interval and Metrics Calculation

    /// Analyze chronological events into valid complete sleep blocks (`[Se durmió] -> [Se despertó]`),
    /// awake intervals, and any incomplete/orphaned events excluded from sleep block calculations.
    public func analyzeTimeline(from events: [SleepEvent]) -> SleepTimelineAnalysis {
        let sorted = events.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var sleepIntervals: [SleepInterval] = []
        var awakeIntervals: [AwakeInterval] = []
        var incompleteEventReasons: [UUID: SleepEventIncompleteReason] = [:]

        var activeSleepEvent: SleepEvent? = nil
        var lastWakeEvent: SleepEvent? = nil

        for event in sorted {
            switch event.type {
            case .sleep:
                if let previousSleep = activeSleepEvent {
                    // Consecutive sleep without an intervening wake: mark previous as incomplete and exclude it.
                    incompleteEventReasons[previousSleep.id] = .missingSubsequentWake(isLatestTimelineEvent: false)
                }
                activeSleepEvent = event

                if let wake = lastWakeEvent {
                    awakeIntervals.append(AwakeInterval(wakeEvent: wake, nextSleepEvent: event))
                    lastWakeEvent = nil
                }

            case .wake:
                if let sleep = activeSleepEvent {
                    sleepIntervals.append(SleepInterval(startEvent: sleep, endEvent: event, classification: sleep.classification))
                    activeSleepEvent = nil
                    lastWakeEvent = event
                } else {
                    // Orphan wake without a preceding valid sleep: ignore in sleep block calculation and flag as incomplete.
                    incompleteEventReasons[event.id] = .missingPrecedingSleep
                }

            case .bedtimeRoutineStart, .sleepAttempt:
                // Non-boundary metadata events
                break
            }
        }

        // Trailing sleep without a subsequent wake is excluded until completed.
        if let remainingSleep = activeSleepEvent {
            incompleteEventReasons[remainingSleep.id] = .missingSubsequentWake(isLatestTimelineEvent: true)
        }

        // Check active awake window
        if let wake = lastWakeEvent {
            awakeIntervals.append(AwakeInterval(wakeEvent: wake, nextSleepEvent: nil))
        }

        return SleepTimelineAnalysis(
            sleepIntervals: sleepIntervals,
            awakeIntervals: awakeIntervals,
            incompleteEventReasons: incompleteEventReasons
        )
    }

    /// Compute valid completed sleep intervals and awake intervals from ordered events.
    /// Safely handles out-of-order, consecutive duplicates, or incomplete sequences.
    public func computeIntervals(from events: [SleepEvent]) -> (sleepIntervals: [SleepInterval], awakeIntervals: [AwakeInterval]) {
        let analysis = analyzeTimeline(from: events)
        return (analysis.sleepIntervals, analysis.awakeIntervals)
    }

    /// Calculate metrics for a 24-hour sleep day.
    /// Only complete valid `[Se durmió] -> [Se despertó]` pairs contribute to sleep blocks and durations.
    public func calculateDayMetrics(for targetDate: Date, calendar: Calendar = .current) throws -> DayMetrics {
        let startOfDay = calendar.startOfDay(for: targetDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw SleepTrackingError.invalidTimestamp("No se pudo calcular el rango del día.")
        }

        // Fetch full timeline chronologically so cross-day pairing is always consistent
        let allEvents = try database.fetchAllEvents(ascending: true)
        let analysis = analyzeTimeline(from: allEvents)
        let allSleeps = analysis.sleepIntervals
        let allAwakes = analysis.awakeIntervals

        // Find completed sleep intervals that belong to or intersect targetDate
        let daySleeps = allSleeps.filter { interval in
            guard let end = interval.endTime else { return false }
            let start = interval.startTime
            // Check intersection with startOfDay...endOfDay
            return start < endOfDay && end > startOfDay
        }

        let dayAwakes = allAwakes.filter { interval in
            let start = interval.startTime
            let end = interval.endTime ?? Date()
            return start < endOfDay && end > startOfDay
        }

        // Morning wake time: first wake event occurring in this calendar day between 04:00 and 12:00
        let morningWake = allEvents.first { event in
            guard event.type == .wake else { return false }
            guard event.timestamp >= startOfDay && event.timestamp < endOfDay else { return false }
            let hour = calendar.component(.hour, from: event.timestamp)
            return hour >= 4 && hour < 12
        }?.timestamp

        // Night sleep onset: sleep event classified as nightSleep
        let dayEvents = allEvents.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        let nightSleepOnset = dayEvents.first { $0.type == .sleep && $0.classification == .nightSleep }?.timestamp

        // Durations calculation (clipped to this day's boundary for precise day metrics)
        var totalDaytimeSleep: TimeInterval = 0
        var totalNightSleep: TimeInterval = 0
        var totalSleep: TimeInterval = 0
        var completedNapsCount = 0

        for interval in daySleeps {
            guard let endTime = interval.endTime else { continue }
            let intervalStart = max(startOfDay, interval.startTime)
            let intervalEnd = min(endOfDay, endTime)
            let effectiveDuration = max(0, intervalEnd.timeIntervalSince(intervalStart))

            totalSleep += effectiveDuration

            let config = SleepConfigurationManager.shared.configuration
            let isNap = interval.classification == .nap || (interval.classification == .unspecified && config.isDayTime(for: interval.startTime, calendar: calendar))

            if isNap {
                totalDaytimeSleep += effectiveDuration
                if interval.isCompleted {
                    completedNapsCount += 1
                }
            } else {
                totalNightSleep += effectiveDuration
            }
        }

        return DayMetrics(
            date: startOfDay,
            morningWakeTime: morningWake,
            sleepIntervals: daySleeps,
            awakeIntervals: dayAwakes,
            completedNapsCount: completedNapsCount,
            totalDaytimeSleepDuration: totalDaytimeSleep,
            totalNightSleepDuration: totalNightSleep,
            totalSleepDuration: totalSleep,
            nightSleepOnset: nightSleepOnset
        )
    }
}
