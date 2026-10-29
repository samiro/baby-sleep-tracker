import WidgetKit
import SwiftUI
import AppIntents

public struct SleepWidgetEntry: TimelineEntry {
    public let date: Date
    public let state: CurrentSleepState
    public let mostRecentInterval: SleepInterval?
    public let statusMessage: String?

    public init(
        date: Date = Date(),
        state: CurrentSleepState = .awake(since: Date().addingTimeInterval(-3600), event: nil),
        mostRecentInterval: SleepInterval? = nil,
        statusMessage: String? = nil
    ) {
        self.date = date
        self.state = state
        self.mostRecentInterval = mostRecentInterval
        self.statusMessage = statusMessage
    }
}

public struct SleepTimelineProvider: TimelineProvider {
    public typealias Entry = SleepWidgetEntry

    public init() {}

    public func placeholder(in context: Context) -> SleepWidgetEntry {
        SleepWidgetEntry(
            date: Date(),
            state: .sleeping(since: Date().addingTimeInterval(-1800), event: SleepEvent(type: .sleep, timestamp: Date().addingTimeInterval(-1800))),
            mostRecentInterval: nil,
            statusMessage: nil
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (SleepWidgetEntry) -> Void) {
        let entry = currentEntry()
        completion(entry)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SleepWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 15 minutes or when App Intent triggers reloadAllTimelines
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func currentEntry() -> SleepWidgetEntry {
        let service = SleepTrackingService.shared
        let state = (try? service.getCurrentState()) ?? .unknown
        let recent = try? service.getMostRecentSleepInterval()

        return SleepWidgetEntry(
            date: Date(),
            state: state,
            mostRecentInterval: recent,
            statusMessage: nil
        )
    }
}

@main
public struct BabySleepTrackerWidgetBundle: WidgetBundle {
    public init() {}

    public var body: some Widget {
        BabySleepTrackerWidget()
        BabySleepTrackerLiveActivityWidget()
    }
}

public struct BabySleepTrackerWidget: Widget {
    public let kind: String = "EmanuelSleepWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepTimelineProvider()) { entry in
            EmanuelSleepWidgetMediumView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Emanuel · Sueño")
        .description("Registra el sueño y vigilia de Emanuel en un toque.")
        .supportedFamilies([.systemMedium])
    }
}
