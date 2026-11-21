import XCTest

final class SleepIntervalTests: XCTestCase {
    var tempDirectory: URL!
    var database: SQLiteDatabase!
    var service: SleepTrackingService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let dbURL = tempDirectory.appendingPathComponent("test.sqlite3")
        database = try SQLiteDatabase(url: dbURL)
        service = SleepTrackingService(database: database)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testSingleCompletedNapDuration() throws {
        let baseDate = Date()
        let sleepTime = baseDate
        let wakeTime = baseDate.addingTimeInterval(5400) // 1 hour 30 mins

        let sleepEvent = SleepEvent(type: .sleep, timestamp: sleepTime, classification: .nap)
        let wakeEvent = SleepEvent(type: .wake, timestamp: wakeTime)

        let (sleeps, _) = service.computeIntervals(from: [sleepEvent, wakeEvent])

        XCTAssertEqual(sleeps.count, 1)
        let interval = sleeps[0]
        XCTAssertTrue(interval.isCompleted)
        XCTAssertEqual(interval.duration, 5400, accuracy: 0.1)
        XCTAssertEqual(interval.formattedDuration, "1h 30m")
        XCTAssertEqual(interval.classification, .nap)
    }

    func testIncompleteActiveSleepIntervalIsExcludedUntilCompleted() throws {
        let sleepTime = Date().addingTimeInterval(-1800) // 30 mins ago
        let sleepEvent = SleepEvent(type: .sleep, timestamp: sleepTime, classification: .nap)

        let analysis = service.analyzeTimeline(from: [sleepEvent])

        XCTAssertTrue(analysis.sleepIntervals.isEmpty)
        XCTAssertEqual(
            analysis.incompleteEventReasons[sleepEvent.id],
            .missingSubsequentWake(isLatestTimelineEvent: true)
        )
        let reason = analysis.incompleteEventReasons[sleepEvent.id]
        XCTAssertEqual(reason?.badgeTitle, "En curso")
        XCTAssertTrue(reason?.isOngoing == true)
        XCTAssertNil(reason?.explanationMessage)
    }

    func testConsecutiveSleepEventsPairSecondWithWakeAndFlagFirstAsIncomplete() throws {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 10
        comps.minute = 0
        let tA = calendar.date(from: comps)!
        let tB = tA.addingTimeInterval(3600) // 11:00
        let tC = tA.addingTimeInterval(7200) // 12:00

        let sleepA = SleepEvent(type: .sleep, timestamp: tA, classification: .nap)
        let sleepB = SleepEvent(type: .sleep, timestamp: tB, classification: .nap)
        let wakeC = SleepEvent(type: .wake, timestamp: tC)

        let analysis = service.analyzeTimeline(from: [sleepA, sleepB, wakeC])

        // Only B -> C forms a valid sleep block
        XCTAssertEqual(analysis.sleepIntervals.count, 1)
        XCTAssertEqual(analysis.sleepIntervals[0].startEvent.id, sleepB.id)
        XCTAssertEqual(analysis.sleepIntervals[0].endEvent?.id, wakeC.id)
        XCTAssertEqual(analysis.sleepIntervals[0].duration, 3600, accuracy: 0.1)

        // A is flagged as incomplete; B and C are complete
        XCTAssertEqual(analysis.incompleteEventReasons.count, 1)
        let reasonA = analysis.incompleteEventReasons[sleepA.id]
        XCTAssertEqual(reasonA, .missingSubsequentWake(isLatestTimelineEvent: false))
        XCTAssertEqual(
            reasonA?.explanationMessage,
            "Evento incompleto: falta registrar el evento 'Se despertó' posterior para incluirlo en los bloques de sueño."
        )
        XCTAssertNil(analysis.incompleteEventReasons[sleepB.id])
        XCTAssertNil(analysis.incompleteEventReasons[wakeC.id])
    }

    func testLeadingWakeStartsValidAwakeIntervalAndOnlyConsecutiveWakesAreFlaggedIncomplete() throws {
        let t0 = Date().addingTimeInterval(-10800)
        let leadingWake = SleepEvent(type: .wake, timestamp: t0)
        let sleep1 = SleepEvent(type: .sleep, timestamp: t0.addingTimeInterval(1800), classification: .nap)
        let wake1 = SleepEvent(type: .wake, timestamp: t0.addingTimeInterval(5400))
        let duplicateWake = SleepEvent(type: .wake, timestamp: t0.addingTimeInterval(7200))

        let analysis = service.analyzeTimeline(from: [leadingWake, sleep1, wake1, duplicateWake])

        XCTAssertEqual(analysis.sleepIntervals.count, 1)
        XCTAssertEqual(analysis.sleepIntervals[0].startEvent.id, sleep1.id)
        XCTAssertEqual(analysis.sleepIntervals[0].endEvent?.id, wake1.id)
        XCTAssertEqual(analysis.sleepIntervals[0].duration, 3600, accuracy: 0.1)

        // Leading wake -> sleep1 forms a valid completed awake interval (30 min)
        XCTAssertEqual(analysis.awakeIntervals.count, 2)
        XCTAssertEqual(analysis.awakeIntervals[0].wakeEvent.id, leadingWake.id)
        XCTAssertEqual(analysis.awakeIntervals[0].nextSleepEvent?.id, sleep1.id)
        XCTAssertEqual(analysis.awakeIntervals[0].duration, 1800, accuracy: 0.1)

        // Leading wake is NOT incomplete; only the consecutive duplicate wake is flagged
        XCTAssertEqual(analysis.incompleteEventReasons.count, 1)
        XCTAssertNil(analysis.incompleteEventReasons[leadingWake.id])
        XCTAssertEqual(analysis.incompleteEventReasons[duplicateWake.id], .missingPrecedingSleep)
        XCTAssertEqual(
            analysis.incompleteEventReasons[duplicateWake.id]?.explanationMessage,
            "Evento incompleto: falta registrar el evento 'Se durmió' anterior para incluirlo en los bloques de sueño."
        )
    }

    func testCycleStartingWithWakeThenSleepIsValidWhileCrossCycleConsecutiveEventsStayFlagged() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        // Nov 17 19:07 wake -> Nov 18 11:07 sleep (16h awake) -> Nov 18 12:30 wake (1h 23m sleep)
        let wakeNov17 = SleepEvent(
            type: .wake,
            timestamp: calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 19, minute: 7))!
        )
        let sleepNov18 = SleepEvent(
            type: .sleep,
            timestamp: calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 11, minute: 7))!,
            classification: .nap
        )
        let wakeNov18 = SleepEvent(
            type: .wake,
            timestamp: calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12, minute: 30))!
        )

        let validAnalysis = service.analyzeTimeline(from: [wakeNov17, sleepNov18, wakeNov18])
        XCTAssertTrue(validAnalysis.incompleteEventReasons.isEmpty)
        XCTAssertEqual(validAnalysis.awakeIntervals.first?.wakeEvent.id, wakeNov17.id)
        XCTAssertEqual(validAnalysis.awakeIntervals.first?.nextSleepEvent?.id, sleepNov18.id)
        XCTAssertEqual(validAnalysis.awakeIntervals.first?.duration ?? 0, 16 * 3600, accuracy: 1.0)
        XCTAssertEqual(validAnalysis.sleepIntervals.count, 1)

        // Consecutive wakes across a cycle boundary (Nov 18 12:30 wake -> Nov 18 20:00 wake) MUST still be flagged
        let consecutiveWakeNextCycle = SleepEvent(
            type: .wake,
            timestamp: calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 20, minute: 0))!
        )
        let crossCycleWakeAnalysis = service.analyzeTimeline(from: [wakeNov17, sleepNov18, wakeNov18, consecutiveWakeNextCycle])
        XCTAssertEqual(crossCycleWakeAnalysis.incompleteEventReasons[consecutiveWakeNextCycle.id], .missingPrecedingSleep)
        XCTAssertNil(crossCycleWakeAnalysis.incompleteEventReasons[wakeNov17.id])

        // Consecutive sleeps across a cycle boundary MUST still flag the earlier sleep
        let sleepCycle1 = SleepEvent(
            type: .sleep,
            timestamp: calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 18, minute: 0))!,
            classification: .nap
        )
        let sleepCycle2 = SleepEvent(
            type: .sleep,
            timestamp: calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 21, minute: 0))!,
            classification: .nightSleep
        )
        let crossCycleSleepAnalysis = service.analyzeTimeline(from: [sleepCycle1, sleepCycle2])
        XCTAssertEqual(
            crossCycleSleepAnalysis.incompleteEventReasons[sleepCycle1.id],
            .missingSubsequentWake(isLatestTimelineEvent: false)
        )
    }

    func testAddingMissingEventInChronologicalOrderCompletesBlockAndClearsWarning() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9, minute: 0))!
        let tSleepA = day
        let tMissingWake = day.addingTimeInterval(3600) // 10:00
        let tSleepB = day.addingTimeInterval(7200) // 11:00
        let tWakeC = day.addingTimeInterval(10800) // 12:00

        let sleepA = try service.recordEvent(type: .sleep, timestamp: tSleepA, classification: .nap, force: true)
        let sleepB = try service.recordEvent(type: .sleep, timestamp: tSleepB, classification: .nap, force: true)
        let wakeC = try service.recordEvent(type: .wake, timestamp: tWakeC, force: true)

        // Before filling the missing wake: only B -> C counts (1h) and A is incomplete
        var metrics = try service.calculateDayMetrics(for: day, calendar: calendar)
        XCTAssertEqual(metrics.sleepIntervals.count, 1)
        XCTAssertEqual(metrics.completedNapsCount, 1)
        XCTAssertEqual(metrics.totalDaytimeSleepDuration, 3600, accuracy: 1.0)
        var incomplete = try service.fetchIncompleteEventReasons()
        XCTAssertEqual(incomplete, [sleepA.id: .missingSubsequentWake(isLatestTimelineEvent: false)])

        // Add the missing wake event chronologically between A and B
        _ = try service.recordEvent(type: .wake, timestamp: tMissingWake, force: true)

        // Now both A -> missingWake and B -> C are complete (2h total) and all warnings disappear
        metrics = try service.calculateDayMetrics(for: day, calendar: calendar)
        XCTAssertEqual(metrics.sleepIntervals.count, 2)
        XCTAssertEqual(metrics.completedNapsCount, 2)
        XCTAssertEqual(metrics.totalDaytimeSleepDuration, 7200, accuracy: 1.0)
        XCTAssertEqual(metrics.sleepIntervals[0].startEvent.id, sleepA.id)
        XCTAssertEqual(metrics.sleepIntervals[1].startEvent.id, sleepB.id)
        XCTAssertEqual(metrics.sleepIntervals[1].endEvent?.id, wakeC.id)

        incomplete = try service.fetchIncompleteEventReasons()
        XCTAssertTrue(incomplete.isEmpty)
    }

    func testOvernightCompletedPairHasNoIncompleteWarningsAcrossDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!

        let nightSleep = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 21, minute: 0))!
        let morningWake = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 7, minute: 0))!

        try service.recordEvent(type: .sleep, timestamp: nightSleep, classification: .nightSleep, force: true)
        try service.recordEvent(type: .wake, timestamp: morningWake, force: true)

        let incomplete = try service.fetchIncompleteEventReasons()
        XCTAssertTrue(incomplete.isEmpty)
    }

    func testAwakeIntervalBetweenNaps() throws {
        let t0 = Date()
        let nap1Sleep = SleepEvent(type: .sleep, timestamp: t0)
        let nap1Wake = SleepEvent(type: .wake, timestamp: t0.addingTimeInterval(3600)) // 1h sleep
        let nap2Sleep = SleepEvent(type: .sleep, timestamp: t0.addingTimeInterval(9000)) // 1.5h awake
        let nap2Wake = SleepEvent(type: .wake, timestamp: t0.addingTimeInterval(12600))

        let (sleeps, awakes) = service.computeIntervals(from: [nap1Sleep, nap1Wake, nap2Sleep, nap2Wake])

        XCTAssertEqual(sleeps.count, 2)
        // 1 completed awake window between naps + 1 active ongoing awake window after nap2
        XCTAssertEqual(awakes.count, 2)

        let completedAwake = awakes[0]
        XCTAssertEqual(completedAwake.duration, 5400, accuracy: 0.1) // 1h 30m wake window
        XCTAssertEqual(completedAwake.formattedDuration, "1h 30m")
        XCTAssertNotNil(completedAwake.nextSleepEvent)

        let activeAwake = awakes[1]
        XCTAssertNil(activeAwake.nextSleepEvent)
    }

    func testMostRecentIntervalWhenEmpty() throws {
        let interval = try service.getMostRecentInterval()
        XCTAssertNil(interval)
    }

    func testMostRecentIntervalWhenSleeping() throws {
        let sleepTime = Date().addingTimeInterval(-1800)
        try service.recordEvent(type: .sleep, timestamp: sleepTime, classification: .nap)

        guard let interval = try service.getMostRecentInterval() else {
            XCTFail("Expected most recent interval to exist")
            return
        }

        XCTAssertEqual(interval.statusText, "Dormido")
        if case .sleep(let sleepInterval) = interval {
            XCTAssertFalse(sleepInterval.isCompleted)
            XCTAssertNil(sleepInterval.endTime)
        } else {
            XCTFail("Expected .sleep interval")
        }
    }

    func testMostRecentIntervalWhenAwake() throws {
        let sleepTime = Date().addingTimeInterval(-7200)
        let wakeTime = Date().addingTimeInterval(-3600)
        try service.recordEvent(type: .sleep, timestamp: sleepTime, classification: .nap)
        try service.recordEvent(type: .wake, timestamp: wakeTime)

        guard let interval = try service.getMostRecentInterval() else {
            XCTFail("Expected most recent interval to exist")
            return
        }

        XCTAssertEqual(interval.statusText, "Despierto")
        if case .awake(let awakeInterval) = interval {
            XCTAssertFalse(awakeInterval.isCompleted)
            XCTAssertNil(awakeInterval.nextSleepEvent)
        } else {
            XCTFail("Expected .awake interval")
        }
    }

    func testMostRecentIntervalAlternatingSequences() throws {
        let t0 = Date().addingTimeInterval(-10800)
        let t1 = Date().addingTimeInterval(-7200)
        let t2 = Date().addingTimeInterval(-3600)

        // Sleep 1
        try service.recordEvent(type: .sleep, timestamp: t0, classification: .nap)
        var interval = try service.getMostRecentInterval()
        XCTAssertEqual(interval?.statusText, "Dormido")

        // Wake 1
        try service.recordEvent(type: .wake, timestamp: t1)
        interval = try service.getMostRecentInterval()
        XCTAssertEqual(interval?.statusText, "Despierto")

        // Sleep 2
        try service.recordEvent(type: .sleep, timestamp: t2, classification: .nap)
        interval = try service.getMostRecentInterval()
        XCTAssertEqual(interval?.statusText, "Dormido")
    }

    func testAwakeIntervalSummaryText() throws {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 10
        comps.minute = 0
        let t0 = calendar.date(from: comps)!
        let t1 = t0.addingTimeInterval(5400) // 11:30 (1h 30m)

        let wakeEvent = SleepEvent(type: .wake, timestamp: t0)
        let sleepEvent = SleepEvent(type: .sleep, timestamp: t1)

        let completedAwake = AwakeInterval(wakeEvent: wakeEvent, nextSleepEvent: sleepEvent)
        XCTAssertEqual(completedAwake.summaryText, "10:00 - 11:30 (1h 30m)")

        let ongoingAwake = AwakeInterval(wakeEvent: wakeEvent, nextSleepEvent: nil)
        XCTAssertTrue(ongoingAwake.summaryText.hasPrefix("10:00 - Ahora"))
    }
}
