import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct SleepActivityAttributes: ActivityAttributes {
    public static let lockScreenWidgetURL = URL(string: "babysleeptracker://today")!

    public struct ContentState: Codable, Hashable, Sendable {
        public var isSleeping: Bool
        public var startDate: Date
        public var statusTitle: String // "Durmiendo" or "Despierto"
        public var babyName: String
        public var hasStartDate: Bool

        private enum CodingKeys: String, CodingKey {
            case isSleeping
            case startDate
            case statusTitle
            case babyName
            case hasStartDate
        }

        public init(
            isSleeping: Bool,
            startDate: Date,
            statusTitle: String,
            babyName: String = "Baby Sleep Tracker",
            hasStartDate: Bool = true
        ) {
            self.isSleeping = isSleeping
            self.startDate = startDate
            self.statusTitle = statusTitle
            self.babyName = babyName
            self.hasStartDate = hasStartDate
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isSleeping = try container.decode(Bool.self, forKey: .isSleeping)
            self.startDate = try container.decode(Date.self, forKey: .startDate)
            self.statusTitle = try container.decode(String.self, forKey: .statusTitle)
            self.babyName = try container.decodeIfPresent(String.self, forKey: .babyName) ?? "Baby Sleep Tracker"
            self.hasStartDate = try container.decodeIfPresent(Bool.self, forKey: .hasStartDate) ?? true
        }

        public var actionButtonTitle: String {
            isSleeping ? "Se despertó" : "Se durmió"
        }

        public var actionButtonIcon: String {
            isSleeping ? "sun.max.fill" : "moon.fill"
        }

        public var statusIcon: String {
            isSleeping ? "moon.stars.fill" : "sun.max.fill"
        }
    }

    public var babyName: String

    public init(babyName: String = "Baby Sleep Tracker") {
        self.babyName = babyName
    }
}
#endif
