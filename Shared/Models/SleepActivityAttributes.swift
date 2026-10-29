import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct SleepActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var isSleeping: Bool
        public var startDate: Date
        public var statusTitle: String // "Durmiendo" or "Despierto"
        public var babyName: String

        public init(
            isSleeping: Bool,
            startDate: Date,
            statusTitle: String,
            babyName: String = "Emanuel"
        ) {
            self.isSleeping = isSleeping
            self.startDate = startDate
            self.statusTitle = statusTitle
            self.babyName = babyName
        }
    }

    public var babyName: String

    public init(babyName: String = "Emanuel") {
        self.babyName = babyName
    }
}
#endif
