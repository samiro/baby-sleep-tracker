import XCTest

final class ConcurrencyAndPersistenceTests: XCTestCase {
    var tempDirectory: URL!
    var dbURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dbURL = tempDirectory.appendingPathComponent("concurrency_test.sqlite3")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testConcurrentWritesInWALMode() throws {
        let db = try SQLiteDatabase(url: dbURL)
        let writeCount = 50
        let expectation = XCTestExpectation(description: "All concurrent writes finish")
        expectation.expectedFulfillmentCount = writeCount

        DispatchQueue.concurrentPerform(iterations: writeCount) { i in
            do {
                let event = SleepEvent(
                    id: UUID(),
                    type: i % 2 == 0 ? .sleep : .wake,
                    timestamp: Date().addingTimeInterval(Double(i * 10)),
                    notes: "Concurrent write #\(i)"
                )
                try db.insertEvent(event)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent write failed at index \(i): \(error)")
            }
        }

        wait(for: [expectation], timeout: 10.0)

        let all = try db.fetchAllEvents()
        XCTAssertEqual(all.count, writeCount)
    }

    func testPersistenceAcrossDatabaseReopening() throws {
        let eventId = UUID()
        let now = Date()

        // Open database 1, write event, and close
        do {
            let db1 = try SQLiteDatabase(url: dbURL)
            let event = SleepEvent(id: eventId, type: .sleep, timestamp: now, classification: .nap, notes: "Persisted")
            try db1.insertEvent(event)
            db1.closeDatabase()
        }

        // Open database 2 (simulating fresh launch) and verify event exists
        do {
            let db2 = try SQLiteDatabase(url: dbURL)
            let retrieved = try db2.fetchEvent(id: eventId)
            XCTAssertNotNil(retrieved)
            XCTAssertEqual(retrieved?.id, eventId)
            XCTAssertEqual(retrieved?.type, .sleep)
            XCTAssertEqual(retrieved?.classification, .nap)
            XCTAssertEqual(retrieved?.notes, "Persisted")
            XCTAssertEqual(retrieved!.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        }
    }

    func testTransactionRollbackOnFailure() throws {
        let db = try SQLiteDatabase(url: dbURL)
        let originalCount = try db.fetchAllEvents().count

        enum DummyError: Error {
            case intentionalFailure
        }

        XCTAssertThrowsError(
            try db.performTransaction {
                try db.insertEvent(SleepEvent(type: .sleep, timestamp: Date()))
                // Intentionally throw error before commit
                throw DummyError.intentionalFailure
            }
        )

        // Count should not have changed due to rollback
        let finalCount = try db.fetchAllEvents().count
        XCTAssertEqual(finalCount, originalCount)
    }
}
