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

    public static func clampedInitialTimestamp(_ initialDate: Date, now: Date = Date()) -> Date {
        min(initialDate, now)
    }

    public static func validatedTimestamp(
        _ timestamp: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Date {
        guard timestamp > now else {
            return timestamp
        }

        // DatePicker with [.date, .hourAndMinute] can preserve a seconds component
        // from its previous Date value even when the user selects the current minute.
        if calendar.isDate(timestamp, equalTo: now, toGranularity: .minute) {
            return now
        }

        throw SleepEventFormValidationError.futureTimestamp
    }

    public static func automaticClassification(
        for type: EventType,
        timestamp: Date,
        configuration: SleepScheduleConfiguration,
        calendar: Calendar = .current
    ) -> SleepClassification {
        guard type == .sleep else {
            return .unspecified
        }
        return configuration.classify(timestamp: timestamp, calendar: calendar)
    }

    public static func makeValidatedFormEvent(
        existingEvent: SleepEvent? = nil,
        type: EventType,
        timestamp: Date,
        notes: String?,
        configuration: SleepScheduleConfiguration,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SleepEvent {
        let effectiveTimestamp = try validatedTimestamp(timestamp, now: now, calendar: calendar)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        let classification = automaticClassification(
            for: type,
            timestamp: effectiveTimestamp,
            configuration: configuration,
            calendar: calendar
        )

        return SleepEvent(
            id: existingEvent?.id ?? UUID(),
            type: type,
            timestamp: effectiveTimestamp,
            classification: classification,
            notes: finalNotes,
            createdAt: existingEvent?.createdAt ?? now,
            updatedAt: now
        )
    }
}

public enum SleepEventFormValidationError: Error, LocalizedError, Equatable, Sendable {
    case futureTimestamp

    public var errorDescription: String? {
        switch self {
        case .futureTimestamp:
            return "No se pueden registrar eventos en fechas futuras."
        }
    }
}
