import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

public struct BabySleepTrackerLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            // Compact presentation for Lock Screen / notification banner
            SleepActivityCompactView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island (Minimal, non-intrusive)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.indigo)
                        Text("Durmiendo")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startDate, style: .timer)
                        .monospacedDigit()
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.indigo)
                }
            } compactLeading: {
                // MARK: - Notch Left Wing: Compact Moon Icon
                // Kept strictly minimal so status bar clock (hora) is NEVER obscured
                Image(systemName: "moon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
            } compactTrailing: {
                // MARK: - Notch Right Wing: Compact Elapsed Timer
                // Kept strictly minimal so status bar battery (carga) is NEVER obscured
                Text(context.state.startDate, style: .timer)
                    .monospacedDigit()
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.indigo)
            } minimal: {
                // MARK: - Minimal Presentation
                Image(systemName: "moon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
            }
            .keylineTint(Color.indigo)
            .widgetURL(URL(string: "emanuelsleep://history"))
        }
    }
}

// MARK: - Compact Presentation for Lock Screen / Banner
public struct SleepActivityCompactView: View {
    let context: ActivityViewContext<SleepActivityAttributes>

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.indigo)

            Text("Durmiendo")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text(context.state.startDate, style: .timer)
                .monospacedDigit()
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.indigo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .widgetURL(URL(string: "emanuelsleep://history"))
    }
}
