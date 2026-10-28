import Foundation

public enum SleepClassification: String, Codable, CaseIterable, Sendable {
    case unspecified = "unspecified"
    case nap = "nap"
    case nightSleep = "night_sleep"

    public var displayName: String {
        switch self {
        case .unspecified:
            return "Sin clasificar"
        case .nap:
            return "Siesta"
        case .nightSleep:
            return "Sueño nocturno"
        }
    }

    public var iconName: String {
        switch self {
        case .unspecified:
            return "questionmark.circle"
        case .nap:
            return "sun.haze.fill"
        case .nightSleep:
            return "moon.zzz.fill"
        }
    }
}
