# Emanuel Sleep Tracker for iPhone 🌙☀️

Minimalist, reliable native iOS app and interactive Home Screen widget for tracking an infant's sleep and wake schedule. Built for one-handed use and sleep-deprived parents. Routine tracking can be performed entirely from the Home Screen widget via App Intents without opening the app.

---

## Features

- **Interactive Medium Widget ("Emanuel · Sueño")**:
  - Live state indicator (🌙 Durmiendo / ☀️ Despierto) with distinctive color accents.
  - Live elapsed time counter updating via native WidgetKit system timers without background battery drain.
  - Most recent sleep interval summary (e.g. `14:15 - 15:45 (1h 30m)`).
  - One-tap App Intent action buttons:
    - **"Se durmió"**: Starts sleep interval.
    - **"Despertó"**: Closes sleep interval and calculates duration.
    - **"Iniciar rutina"**: Secondary action to log bedtime routine onset.
  - Deep link to the history screen (`emanuelsleep://history`).

- **Companion App**:
  - Big one-handed action buttons with real-time state synchronization.
  - Daily summary metrics card:
    - Morning wake time.
    - Number of completed naps.
    - Total daytime sleep duration.
    - Night sleep onset time.
    - Bedtime routine start time.
    - Routine-to-sleep latency.
  - History & Timeline view:
    - Sleep intervals with visual durations.
    - Wake windows (awake intervals between sleeps).
    - Add missed events with custom timestamp and classification.
    - Edit existing event timestamps, classifications, and notes.
    - Delete accidental entries with confirmation dialog.
  - Data Export:
    - Full event log export to **CSV** and **JSON** preserving exact timestamps and event types via native iOS Share sheet.

- **Persistence & Multi-Process Concurrency**:
  - Native C `sqlite3` storage engine with zero third-party dependencies.
  - Configured with `PRAGMA journal_mode = WAL;` (Write-Ahead Logging) and `PRAGMA busy_timeout = 5000;`.
  - Transaction-safe with atomic rollback (`BEGIN IMMEDIATE;`).
  - Shared between app and widget extension via App Group container (`group.com.samiro.babysleeptracker`) with graceful sandbox fallback for isolated testing.

---

## Project Structure

```
baby-sleep-tracker/
├── App/
│   ├── BabySleepTrackerApp.swift       # App entrypoint and deep link handler
│   ├── Views/
│   │   ├── MainDashboardView.swift     # One-handed dashboard with live timer
│   │   ├── TimelineHistoryView.swift   # Day history, date navigation, export
│   │   ├── AddEditEventView.swift      # Add missed event / edit sheet
│   │   └── DailyMetricsCardView.swift  # Daily metrics summary grid
│   ├── Info.plist                      # URL scheme (emanuelsleep://) configuration
│   └── BabySleepTracker.entitlements   # App Group entitlement
├── Widget/
│   ├── BabySleepTrackerWidget.swift    # WidgetKit entrypoint and TimelineProvider
│   ├── WidgetViews.swift               # Medium widget view with interactive buttons
│   ├── Info.plist                      # Widget extension configuration
│   └── BabySleepTrackerWidget.entitlements # Widget App Group entitlement
├── Shared/
│   ├── Models/
│   │   ├── SleepEvent.swift            # Core event model (UUID, timestamp, notes)
│   │   ├── EventType.swift             # sleep, wake, bedtimeRoutineStart, sleepAttempt
│   │   ├── SleepClassification.swift   # nap, nightSleep, unspecified
│   │   ├── SleepInterval.swift         # Paired sleep & awake intervals
│   │   └── DayMetrics.swift            # 24h metrics calculations
│   ├── Storage/
│   │   ├── SQLiteDatabase.swift        # WAL-mode multi-process SQLite engine
│   │   ├── DatabaseError.swift         # Localized database errors
│   │   └── AppGroupCoordinator.swift   # App Group container resolver
│   ├── Services/
│   │   ├── SleepTrackingService.swift  # Business logic, state transitions, validation
│   │   └── ExportService.swift         # CSV and JSON serialisation
│   └── Intents/
│       └── SleepAppIntents.swift       # WidgetKit App Intents
├── Tests/
│   ├── SleepIntervalTests.swift        # Durations, wake windows, active intervals
│   ├── OvernightBoundaryTests.swift    # Intervals crossing midnight (20:30 -> 06:30)
│   ├── DuplicateHandlingTests.swift    # Duplicate taps, 5s debounce, safe errors
│   ├── TimezoneHandlingTests.swift     # Absolute UTC epoch, DST transition integrity
│   ├── ConcurrencyAndPersistenceTests.swift # Multi-threaded writes, restart survival
│   └── ExportTests.swift               # CSV and JSON export fidelity
├── project.yml                         # XcodeGen project specification
└── BabySleepTracker.xcodeproj          # Generated Xcode project
```

---

## Setup & Build

### Prerequisites
- macOS Sonoma or later
- Xcode 15.0+ or Xcode 16+ / 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### 1. Generate Xcode Project
```bash
xcodegen generate
```

### 2. Run Automated Tests
```bash
# Build the test bundle
xcodebuild -project BabySleepTracker.xcodeproj -target BabySleepTrackerTests -sdk iphonesimulator -arch arm64 build

# Execute tests on booted simulator
xcrun simctl spawn booted /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest build/Debug-iphonesimulator/BabySleepTrackerTests.xctest
```

**Test results (15/15 passing, 0 failures):**
- `ConcurrencyAndPersistenceTests`: `testConcurrentWritesInWALMode`, `testPersistenceAcrossDatabaseReopening`, `testTransactionRollbackOnFailure`
- `DuplicateHandlingTests`: `testConsecutiveSleepThrowsError`, `testConsecutiveWakeThrowsError`, `testForceRecordAllowsCorrection`, `testRapidDebounceWithin5SecondsReturnsSameEvent`
- `ExportTests`: `testCSVExportPreservesDataAndFormatsCorrectly`, `testJSONExportPreservesTypesAndTimestamps`
- `OvernightBoundaryTests`: `testOvernightSleepCrossingMidnight`
- `SleepIntervalTests`: `testSingleCompletedNapDuration`, `testIncompleteActiveSleepInterval`, `testAwakeIntervalBetweenNaps`
- `TimezoneHandlingTests`: `testAbsoluteTimestampPreservedAcrossTimezones`, `testDurationAcrossDaylightSavingTransition`

### 3. Build & Run App on Simulator
```bash
# Build main app with embedded widget
xcodebuild -project BabySleepTracker.xcodeproj -target BabySleepTracker -sdk iphonesimulator -arch arm64 build

# Install on simulator
xcrun simctl install booted build/Debug-iphonesimulator/BabySleepTracker.app

# Launch app
xcrun simctl launch booted com.samiro.babysleeptracker
```

### 4. Adding the Widget to Home Screen
1. On the iPhone Simulator (or device), swipe to the Home Screen.
2. Long-press any empty area until icons jiggle.
3. Tap the **"+"** button in the top corner.
4. Search or select **"Emanuel"** or **"Emanuel · Sueño"**.
5. Select the **Medium** widget and tap **"Add Widget"**.
6. Tap "Se durmió" or "Despertó" directly from the widget to verify instant local recording.

---

## Physical Device Installation & Constraints Report

### Environment Status
- **Connected device check**: Devicectl identified `Samir Phone (iPhone15,3)` as currently `unavailable` (device disconnected or locked / not accessible on local network).
- **Code signing**: Local keychain contains no personal or team code signing identity (`security find-identity -p codesigning -v` reported 0 identities).

### Instructions to Run on Physical iPhone
To install on a physical iPhone:
1. Connect the iPhone via USB cable or ensure it is paired wirelessly on the same Wi-Fi network.
2. In Xcode, open `BabySleepTracker.xcodeproj`.
3. Select the `BabySleepTracker` target -> **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Select your **Apple Developer Team**.
4. In the **App Groups** capability for both `BabySleepTracker` and `BabySleepTrackerWidget`, verify that your team has registered an App Group (e.g., `group.<your-team-id>.com.samiro.babysleeptracker`).
   - If using a personal team identifier, update `appGroupId` in `Shared/Storage/AppGroupCoordinator.swift` and the entitlements files accordingly.
5. Select your physical iPhone as the run destination and click **Run** (⌘R).
