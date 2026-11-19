import Foundation

public struct SleepInterval: Identifiable, Equatable, Sendable {
    public var id: UUID { startEvent.id }
    public let startEvent: SleepEvent
    public let endEvent: SleepEvent?
    public let classification: SleepClassification

    public var startTime: Date {
        startEvent.timestamp
    }

    public var endTime: Date? {
        endEvent?.timestamp
    }

    public var isCompleted: Bool {
        endEvent != nil
    }

    public var duration: TimeInterval {
        if let end = endTime {
            return max(0, end.timeIntervalSince(startTime))
        } else {
            return max(0, Date().timeIntervalSince(startTime))
        }
    }

    public init(startEvent: SleepEvent, endEvent: SleepEvent? = nil, classification: SleepClassification? = nil) {
        self.startEvent = startEvent
        self.endEvent = endEvent
        self.classification = classification ?? startEvent.classification
    }

    public var formattedDuration: String {
        let seconds = Int(duration)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    public var summaryText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startStr = formatter.string(from: startTime)
        if let end = endTime {
            let endStr = formatter.string(from: end)
            return "\(startStr) - \(endStr) (\(formattedDuration))"
        } else {
            return "\(startStr) - Ahora (\(formattedDuration))"
        }
    }
}

public struct AwakeInterval: Identifiable, Equatable, Sendable {
    public var id: UUID { wakeEvent.id }
    public let wakeEvent: SleepEvent
    public let nextSleepEvent: SleepEvent?

    public var startTime: Date {
        wakeEvent.timestamp
    }

    public var endTime: Date? {
        nextSleepEvent?.timestamp
    }

    public var isCompleted: Bool {
        nextSleepEvent != nil
    }

    public var duration: TimeInterval {
        if let end = endTime {
            return max(0, end.timeIntervalSince(startTime))
        } else {
            return max(0, Date().timeIntervalSince(startTime))
        }
    }

    public var formattedDuration: String {
        let seconds = Int(duration)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    public var summaryText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startStr = formatter.string(from: startTime)
        if let end = endTime {
            let endStr = formatter.string(from: end)
            return "\(startStr) - \(endStr) (\(formattedDuration))"
        } else {
            return "\(startStr) - Ahora (\(formattedDuration))"
        }
    }

    public init(wakeEvent: SleepEvent, nextSleepEvent: SleepEvent? = nil) {
        self.wakeEvent = wakeEvent
        self.nextSleepEvent = nextSleepEvent
    }
}

public enum TrackedInterval: Identifiable, Equatable, Sendable {
    case sleep(SleepInterval)
    case awake(AwakeInterval)

    public var id: UUID {
        switch self {
        case .sleep(let interval): return interval.id
        case .awake(let interval): return interval.id
        }
    }

    public var startTime: Date {
        switch self {
        case .sleep(let interval): return interval.startTime
        case .awake(let interval): return interval.startTime
        }
    }

    public var endTime: Date? {
        switch self {
        case .sleep(let interval): return interval.endTime
        case .awake(let interval): return interval.endTime
        }
    }

    public var isCompleted: Bool {
        switch self {
        case .sleep(let interval): return interval.isCompleted
        case .awake(let interval): return interval.isCompleted
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .sleep(let interval): return interval.duration
        case .awake(let interval): return interval.duration
        }
    }

    public var formattedDuration: String {
        switch self {
        case .sleep(let interval): return interval.formattedDuration
        case .awake(let interval): return interval.formattedDuration
        }
    }

    public var statusText: String {
        switch self {
        case .sleep: return "Dormido"
        case .awake: return "Despierto"
        }
    }

    public var summaryText: String {
        switch self {
        case .sleep(let interval): return interval.summaryText
        case .awake(let interval): return interval.summaryText
        }
    }
}
