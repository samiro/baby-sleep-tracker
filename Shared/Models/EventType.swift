import Foundation

public enum EventType: String, Codable, CaseIterable, Sendable {
    case sleep = "sleep"
    case wake = "wake"
    case bedtimeRoutineStart = "bedtime_routine_start"
    case sleepAttempt = "sleep_attempt"

    public var displayName: String {
        switch self {
        case .sleep:
            return "Se durmió"
        case .wake:
            return "Despertó"
        case .bedtimeRoutineStart:
            return "Inicio de rutina"
        case .sleepAttempt:
            return "Intento de dormir"
        }
    }

    public var iconName: String {
        switch self {
        case .sleep:
            return "moon.stars.fill"
        case .wake:
            return "sun.max.fill"
        case .bedtimeRoutineStart:
            return "book.closed.fill"
        case .sleepAttempt:
            return "bed.double.fill"
        }
    }
}
