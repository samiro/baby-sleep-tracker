import WidgetKit
import SwiftUI
import AppIntents

public struct SleepWidgetEntry: TimelineEntry {
    public let date: Date
    public let snapshot: MediumWidgetSnapshot

    public init(snapshot: MediumWidgetSnapshot) {
        self.date = snapshot.date
        self.snapshot = snapshot
    }
}

public struct SleepTimelineProvider: TimelineProvider {
    public typealias Entry = SleepWidgetEntry

    public init() {}

    public func placeholder(in context: Context) -> SleepWidgetEntry {
        SleepWidgetEntry(snapshot: MediumWidgetSnapshot.placeholder())
    }

    public func getSnapshot(in context: Context, completion: @escaping (SleepWidgetEntry) -> Void) {
        if context.isPreview {
            completion(SleepWidgetEntry(snapshot: MediumWidgetSnapshot.placeholder()))
            return
        }
        let entry = currentEntry()
        completion(entry)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SleepWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = entry.snapshot.nextRefreshDate()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func currentEntry() -> SleepWidgetEntry {
        let snapshot = MediumWidgetSnapshot.make()
        return SleepWidgetEntry(snapshot: snapshot)
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
        .configurationDisplayName(BabyProfileManager.defaultAppName)
        .description("Consulta el estado actual, el resumen del ciclo 24h y registra el sueño en un toque.")
        .supportedFamilies([.systemMedium])
    }
}
