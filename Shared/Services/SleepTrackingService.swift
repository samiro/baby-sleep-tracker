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
    private let configurationManager: SleepConfigurationManager

    public init(
        database: SQLiteDatabase? = nil,
        configurationManager: SleepConfigurationManager = .shared
    ) {
        self.configurationManager = configurationManager
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
                finalClassification = configurationManager.configuration.classify(timestamp: timestamp)
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
        return try configurationManager.reclassifyUnspecifiedEvents(database: database)
    }

    /// Saves a new 24-hour cycle schedule configuration and retroactively reclassifies
    /// all historical sleep events so past and current cycles stay consistent.
    @discardableResult
    public func applyScheduleConfiguration(
        _ newConfig: SleepScheduleConfiguration,
        calendar: Calendar = .current
    ) throws -> Int {
        let updatedCount = try reclassifyAllSleepEvents(using: newConfig, calendar: calendar, notify: false)
        configurationManager.save(newConfig)
        notifyDataChanged()
        return updatedCount
    }

    /// Retroactively reclassifies every sleep event in storage according to `configuration`
    /// (or the currently saved configuration when omitted).
    @discardableResult
    public func reclassifyAllSleepEvents(
        using configuration: SleepScheduleConfiguration? = nil,
        calendar: Calendar = .current,
        notify: Bool = true
    ) throws -> Int {
        let activeConfig = configuration ?? configurationManager.configuration
        return try database.performTransaction {
            let allEvents = try database.fetchAllEvents(ascending: true)
            var updatedCount = 0

            for event in allEvents where event.type == .sleep {
                let newClassification = activeConfig.classify(timestamp: event.timestamp, calendar: calendar)
                if event.classification != newClassification {
                    var updatedEvent = event
                    updatedEvent.classification = newClassification
                    updatedEvent.updatedAt = Date()
                    try database.updateEvent(updatedEvent)
                    updatedCount += 1
                }
            }

            if notify {
                notifyDataChanged()
            }
            return updatedCount
        }
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

    public func fetchEvents(in cycle: SleepCycleRange) throws -> [SleepEvent] {
        let events = try database.fetchEvents(from: cycle.start, to: cycle.end)
        return events.filter { cycle.contains($0.timestamp) }
    }

    public func fetchEvents(
        for date: Date,
        calendar: Calendar = .current,
        configuration: SleepScheduleConfiguration? = nil
    ) throws -> [SleepEvent] {
        let activeConfig = configuration ?? configurationManager.configuration
        let cycle = activeConfig.cycleRange(containing: date, calendar: calendar)
        return try fetchEvents(in: cycle)
    }

    public func fetchIncompleteEventReasons() throws -> [UUID: SleepEventIncompleteReason] {
        let allEvents = try database.fetchAllEvents(ascending: true)
        return analyzeTimeline(from: allEvents).incompleteEventReasons
    }

    /// Returns the currently ongoing sleep interval when the baby is sleeping and `cycle` is the active cycle
    /// containing `now` (including when the ongoing sleep started in an earlier cycle and is still in progress).
    public func activeSleepInterval(
        in cycle: SleepCycleRange,
        configuration: SleepScheduleConfiguration? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SleepInterval? {
        guard cycle.contains(now) else {
            return nil
        }
        guard case .sleeping(let since, let sleepEvent) = try getCurrentState(),
              since <= now else {
            return nil
        }
        let activeConfig = configuration ?? configurationManager.configuration
        let classification = activeConfig.classify(timestamp: sleepEvent.timestamp, calendar: calendar)
        return SleepInterval(
            startEvent: sleepEvent,
            endEvent: nil,
            classification: classification
        )
    }

    // MARK: - Interval and Metrics Calculation

    /// Analyze chronological events into valid complete sleep blocks (`[Se durmió] -> [Se despertó]`),
    /// awake intervals, and any incomplete/orphaned events excluded from sleep block calculations.
    /// When `configuration` is provided, each sleep interval's classification is computed dynamically
    /// against that 24-hour schedule configuration.
    public func analyzeTimeline(
        from events: [SleepEvent],
        configuration: SleepScheduleConfiguration? = nil,
        calendar: Calendar = .current
    ) -> SleepTimelineAnalysis {
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
        var hasSeenBoundaryEvent = false

        func resolvedClassification(for sleepEvent: SleepEvent) -> SleepClassification {
            if let configuration = configuration {
                return configuration.classify(timestamp: sleepEvent.timestamp, calendar: calendar)
            }
            return sleepEvent.classification
        }

        for event in sorted {
            switch event.type {
            case .sleep:
                hasSeenBoundaryEvent = true
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
                    sleepIntervals.append(
                        SleepInterval(
                            startEvent: sleep,
                            endEvent: event,
                            classification: resolvedClassification(for: sleep)
                        )
                    )
                    activeSleepEvent = nil
                    lastWakeEvent = event
                } else if !hasSeenBoundaryEvent {
                    // Starting the timeline with a wake event is valid; track the awake window until the next sleep.
                    lastWakeEvent = event
                } else {
                    // Consecutive wake without an intervening sleep: ignore in sleep block calculation and flag as incomplete.
                    incompleteEventReasons[event.id] = .missingPrecedingSleep
                }
                hasSeenBoundaryEvent = true

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
    public func computeIntervals(
        from events: [SleepEvent],
        configuration: SleepScheduleConfiguration? = nil,
        calendar: Calendar = .current
    ) -> (sleepIntervals: [SleepInterval], awakeIntervals: [AwakeInterval]) {
        let analysis = analyzeTimeline(from: events, configuration: configuration, calendar: calendar)
        return (analysis.sleepIntervals, analysis.awakeIntervals)
    }

    /// Calculate metrics for the configured 24-hour cycle containing `targetDate`.
    /// Only complete valid `[Se durmió] -> [Se despertó]` pairs contribute to sleep blocks and durations.
    public func calculateDayMetrics(
        for targetDate: Date,
        calendar: Calendar = .current,
        configuration: SleepScheduleConfiguration? = nil,
        now: Date = Date()
    ) throws -> DayMetrics {
        let activeConfig = configuration ?? configurationManager.configuration
        let cycle = activeConfig.cycleRange(containing: targetDate, calendar: calendar)
        return try calculateCycleMetrics(
            for: cycle,
            calendar: calendar,
            configuration: activeConfig,
            now: now
        )
    }

    /// Calculate metrics, completed sleep intervals, and awake intervals strictly bounded by the given 24-hour `cycle`.
    /// Only complete valid `[Se durmió] -> [Se despertó]` pairs contribute to sleep blocks and durations.
    public func calculateCycleMetrics(
        for cycle: SleepCycleRange,
        calendar: Calendar = .current,
        configuration: SleepScheduleConfiguration? = nil,
        now: Date = Date()
    ) throws -> DayMetrics {
        let activeConfig = configuration ?? configurationManager.configuration

        // Fetch full timeline chronologically so cross-cycle pairing and incomplete detection are always consistent
        let allEvents = try database.fetchAllEvents(ascending: true)
        let analysis = analyzeTimeline(
            from: allEvents,
            configuration: activeConfig,
            calendar: calendar
        )
        let allSleeps = analysis.sleepIntervals
        let allAwakes = analysis.awakeIntervals

        // Find completed sleep intervals that belong to or intersect [cycle.start, cycle.end)
        let cycleSleeps = allSleeps.filter { interval in
            guard let end = interval.endTime else { return false }
            let start = interval.startTime
            return cycle.contains(start) || (start < cycle.end && end > cycle.start)
        }

        let cycleAwakes = allAwakes.filter { interval in
            let start = interval.startTime
            let end = interval.endTime ?? now
            return cycle.contains(start) || (start < cycle.end && end > cycle.start)
        }

        let cycleEvents = allEvents.filter { cycle.contains($0.timestamp) }

        // Morning wake time: first wake event occurring in this cycle during morning / day-start window
        let morningWake = cycleEvents.first { event in
            guard event.type == .wake else { return false }
            let hour = calendar.component(.hour, from: event.timestamp)
            let inStandardMorning = hour >= 4 && hour < 12
            let inConfiguredDayStart = event.timestamp >= cycle.dayStart && event.timestamp < cycle.dayStart.addingTimeInterval(4 * 3600)
            return inStandardMorning || inConfiguredDayStart
        }?.timestamp

        // Night sleep onset: first sleep event in this cycle dynamically classified as night sleep
        let nightSleepOnset = cycleEvents.first { event in
            event.type == .sleep && activeConfig.classify(timestamp: event.timestamp, calendar: calendar) == .nightSleep
        }?.timestamp

        // Durations calculation (clipped strictly to this 24-hour cycle's boundaries)
        var totalDaytimeSleep: TimeInterval = 0
        var totalNightSleep: TimeInterval = 0
        var totalSleep: TimeInterval = 0
        var completedNapsCount = 0

        for interval in cycleSleeps {
            guard let endTime = interval.endTime else { continue }
            let intervalStart = max(cycle.start, interval.startTime)
            let intervalEnd = min(cycle.end, endTime)
            let effectiveDuration = max(0, intervalEnd.timeIntervalSince(intervalStart))

            totalSleep += effectiveDuration

            let isNap = interval.classification == .nap
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
            date: cycle.start,
            cycleEnd: cycle.end,
            morningWakeTime: morningWake,
            sleepIntervals: cycleSleeps,
            awakeIntervals: cycleAwakes,
            completedNapsCount: completedNapsCount,
            totalDaytimeSleepDuration: totalDaytimeSleep,
            totalNightSleepDuration: totalNightSleep,
            totalSleepDuration: totalSleep,
            nightSleepOnset: nightSleepOnset
        )
    }
}
