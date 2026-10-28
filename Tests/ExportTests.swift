import XCTest

final class ExportTests: XCTestCase {
    func testCSVExportPreservesDataAndFormatsCorrectly() throws {
        let t0 = Date(timeIntervalSince1970: 1793134800)
        let event1 = SleepEvent(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            type: .sleep,
            timestamp: t0,
            classification: .nap,
            notes: "Con chupón, tranquilo",
            createdAt: t0,
            updatedAt: t0
        )
        let event2 = SleepEvent(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: .wake,
            timestamp: t0.addingTimeInterval(3600),
            classification: .unspecified,
            notes: "Sonriente",
            createdAt: t0.addingTimeInterval(3600),
            updatedAt: t0.addingTimeInterval(3600)
        )

        let csv = ExportService.shared.exportToCSV(events: [event1, event2])
        let lines = csv.split(separator: "\n").map { String($0) }

        XCTAssertEqual(lines.count, 3) // Header + 2 rows
        XCTAssertEqual(lines[0], "id,event_type,timestamp_iso8601,timestamp_epoch,classification,notes,created_at_iso8601,updated_at_iso8601")

        XCTAssertTrue(lines[1].contains("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        XCTAssertTrue(lines[1].contains("sleep"))
        XCTAssertTrue(lines[1].contains("nap"))
        XCTAssertTrue(lines[1].contains("\"Con chupón, tranquilo\""))

        XCTAssertTrue(lines[2].contains("11111111-2222-3333-4444-555555555555"))
        XCTAssertTrue(lines[2].contains("wake"))
    }

    func testJSONExportPreservesTypesAndTimestamps() throws {
        let t0 = Date(timeIntervalSince1970: 1793134800)
        let event = SleepEvent(
            id: UUID(),
            type: .bedtimeRoutineStart,
            timestamp: t0,
            classification: .unspecified,
            notes: "Baño tibio y masaje"
        )

        let jsonData = try ExportService.shared.exportToJSON(events: [event])
        XCTAssertFalse(jsonData.isEmpty)

        // Deserialize as JSON Array
        guard let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            XCTFail("Exported JSON is not an array of dictionaries")
            return
        }

        XCTAssertEqual(jsonArray.count, 1)
        let item = jsonArray[0]
        XCTAssertEqual(item["event_type"] as? String, "bedtime_routine_start")
        XCTAssertEqual(item["id"] as? String, event.id.uuidString)
        XCTAssertEqual(item["notes"] as? String, "Baño tibio y masaje")
        XCTAssertEqual(item["timestamp_epoch"] as? Double, 1793134800)
    }
}
