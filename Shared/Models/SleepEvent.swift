import Foundation

public struct SleepEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var type: EventType
    public var timestamp: Date
    public var classification: SleepClassification
    public var notes: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: EventType,
        timestamp: Date = Date(),
        classification: SleepClassification = .unspecified,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.classification = classification
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
