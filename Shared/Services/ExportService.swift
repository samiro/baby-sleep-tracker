import Foundation

public final class ExportService: Sendable {
    public static let shared = ExportService()

    private let isoFormatter: ISO8601DateFormatter

    public init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    public func exportToCSV(events: [SleepEvent]) -> String {
        var lines: [String] = []
        lines.append("id,event_type,timestamp_iso8601,timestamp_epoch,classification,notes,created_at_iso8601,updated_at_iso8601")

        for event in events {
            let id = event.id.uuidString
            let type = event.type.rawValue
            let timestampIso = isoFormatter.string(from: event.timestamp)
            let timestampEpoch = String(format: "%.3f", event.timestamp.timeIntervalSince1970)
            let classification = event.classification.rawValue
            let notesEscaped = event.notes.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" } ?? ""
            let createdIso = isoFormatter.string(from: event.createdAt)
            let updatedIso = isoFormatter.string(from: event.updatedAt)

            let row = "\(id),\(type),\(timestampIso),\(timestampEpoch),\(classification),\(notesEscaped),\(createdIso),\(updatedIso)"
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    public func exportToJSON(events: [SleepEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        struct ExportItem: Codable {
            let id: UUID
            let event_type: String
            let timestamp_iso8601: String
            let timestamp_epoch: Double
            let classification: String
            let notes: String?
            let created_at_iso8601: String
            let updated_at_iso8601: String
        }

        let items = events.map { event in
            ExportItem(
                id: event.id,
                event_type: event.type.rawValue,
                timestamp_iso8601: isoFormatter.string(from: event.timestamp),
                timestamp_epoch: event.timestamp.timeIntervalSince1970,
                classification: event.classification.rawValue,
                notes: event.notes,
                created_at_iso8601: isoFormatter.string(from: event.createdAt),
                updated_at_iso8601: isoFormatter.string(from: event.updatedAt)
            )
        }

        return try encoder.encode(items)
    }
}
