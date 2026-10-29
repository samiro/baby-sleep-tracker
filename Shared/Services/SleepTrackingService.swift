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
            return "Emanuel ya figura durmiendo desde las \(formatter.string(from: date))."
        case .alreadyAwake(let date):
            return "Emanuel ya figura despierto desde las \(formatter.string(from: date))."
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

            // State validation unless forced
            if !force, let latest = latest {
                // If attempting to record sleep while already sleeping
                if type == .sleep && latest.type == .sleep {
                    // Check if duplicate tap within 5 seconds
                    if abs(timestamp.timeIntervalSince(latest.timestamp)) < 5 {
                        return latest
                    }
                    throw SleepTrackingError.alreadySleeping(latest.timestamp)
                }

                // If attempting to record wake while already awake
                if type == .wake && latest.type == .wake {
                    if abs(timestamp.timeIntervalSince(latest.timestamp)) < 5 {
                        return latest
                    }
                    throw SleepTrackingError.alreadyAwake(latest.timestamp)
                }
            }

            var finalClassification = classification
            if finalClassification == .unspecified && type == .sleep {
                // Suggest daytime vs night sleep based on hour (19:00 - 07:00 is typically night)
                let hour = Calendar.current.component(.hour, from: timestamp)
                if hour >= 19 || hour < 7 {
                    finalClassification = .nightSleep
                } else {
                    finalClassification = .nap
                }
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

    // MARK: - Interval and Metrics Calculation

    /// Compute sleep intervals and awake intervals from ordered events.
    /// Safely handles out-of-order, consecutive duplicates, or incomplete sequences.
    public func computeIntervals(from events: [SleepEvent]) -> (sleepIntervals: [SleepInterval], awakeIntervals: [AwakeInterval]) {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var sleepIntervals: [SleepInterval] = []
        var awakeIntervals: [AwakeInterval] = []

        var activeSleepEvent: SleepEvent? = nil
        var lastWakeEvent: SleepEvent? = nil

        for event in sorted {
            switch event.type {
            case .sleep:
                if let active = activeSleepEvent {
                    // Two consecutive sleep events: close previous as unclosed/orphan or keep latest
                    sleepIntervals.append(SleepInterval(startEvent: active, endEvent: nil))
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
                }
                lastWakeEvent = event

            case .bedtimeRoutineStart, .sleepAttempt:
                // Non-boundary metadata events
                break
            }
        }

        // Check if Emanuel is still sleeping
        if let active = activeSleepEvent {
            sleepIntervals.append(SleepInterval(startEvent: active, endEvent: nil))
        }

        // Check active awake window
        if let wake = lastWakeEvent {
            awakeIntervals.append(AwakeInterval(wakeEvent: wake, nextSleepEvent: nil))
        }

        return (sleepIntervals, awakeIntervals)
    }

    /// Calculate metrics for a 24-hour sleep day.
    /// In pediatric sleep tracking, overnight sleep is assigned to the day it began,
    /// or we attribute intervals intersecting the given date window.
    public func calculateDayMetrics(for targetDate: Date, calendar: Calendar = .current) throws -> DayMetrics {
        let startOfDay = calendar.startOfDay(for: targetDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw SleepTrackingError.invalidTimestamp("No se pudo calcular el rango del día.")
        }

        // Fetch events with 1 day padding before and after to properly calculate overnight intervals
        let windowStart = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let windowEnd = calendar.date(byAdding: .day, value: 2, to: startOfDay) ?? endOfDay

        let allEvents = try database.fetchEvents(from: windowStart, to: windowEnd)
        let (allSleeps, allAwakes) = computeIntervals(from: allEvents)

        // Find intervals that belong to or intersect targetDate
        let daySleeps = allSleeps.filter { interval in
            let start = interval.startTime
            let end = interval.endTime ?? Date()
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

        // Bedtime routine start for this day (usually in evening >= 17:00, or latest routine start before night sleep)
        let dayEvents = try database.fetchEvents(from: startOfDay, to: endOfDay)
        let routineEvent = dayEvents.last { $0.type == .bedtimeRoutineStart }
        let routineStart = routineEvent?.timestamp

        // Night sleep onset: sleep event after routineStart or classified as nightSleep
        var nightSleepOnset: Date? = nil
        if let routineStart = routineStart {
            nightSleepOnset = dayEvents.first { $0.type == .sleep && $0.timestamp >= routineStart }?.timestamp
        }
        if nightSleepOnset == nil {
            nightSleepOnset = dayEvents.first { $0.type == .sleep && $0.classification == .nightSleep }?.timestamp
        }

        var routineToSleep: TimeInterval? = nil
        if let routine = routineStart, let onset = nightSleepOnset, onset >= routine {
            routineToSleep = onset.timeIntervalSince(routine)
        }

        // Durations calculation (clipped to this day's boundary for precise day metrics)
        var totalDaytimeSleep: TimeInterval = 0
        var totalNightSleep: TimeInterval = 0
        var totalSleep: TimeInterval = 0
        var completedNapsCount = 0

        for interval in daySleeps {
            let intervalStart = max(startOfDay, interval.startTime)
            let intervalEnd = min(endOfDay, interval.endTime ?? Date())
            let effectiveDuration = max(0, intervalEnd.timeIntervalSince(intervalStart))

            totalSleep += effectiveDuration

            let isNap = interval.classification == .nap || (interval.classification == .unspecified && calendar.component(.hour, from: interval.startTime) >= 7 && calendar.component(.hour, from: interval.startTime) < 19)

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
            bedtimeRoutineStart: routineStart,
            nightSleepOnset: nightSleepOnset,
            routineToSleepDuration: routineToSleep
        )
    }
}
