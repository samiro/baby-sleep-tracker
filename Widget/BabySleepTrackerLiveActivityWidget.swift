import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

public struct BabySleepTrackerLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            // Persistent interactive presentation for Lock Screen / notification banner
            SleepActivityCompactView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let isSleeping = context.state.isSleeping
            let accentColor: Color = isSleeping ? .indigo : .orange
            let statusIcon = isSleeping ? "moon.fill" : "sun.max.fill"

            return DynamicIsland {
                // MARK: - Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(accentColor)
                        Text(context.state.statusTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.hasStartDate {
                        Text(context.state.startDate, style: .timer)
                            .monospacedDigit()
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(isSleeping ? Color(red: 0.62, green: 0.60, blue: 1.0) : .orange)
                    } else {
                        Text("--:--")
                            .monospacedDigit()
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    SleepActivityActionButton(isSleeping: isSleeping)
                        .padding(.top, 4)
                }
            } compactLeading: {
                // MARK: - Notch Left Wing: Compact State Icon
                // Kept strictly minimal so status bar clock (hora) is NEVER obscured
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 14, height: 14)
            } compactTrailing: {
                // MARK: - Notch Right Wing: Compact Elapsed Timer
                // Frame width constraint is MANDATORY to prevent SwiftUI Text(style: .timer)
                // from requesting infinite width and forcing iOS SpringBoard to stretch the island
                // and hide the status bar clock and battery.
                if context.state.hasStartDate {
                    Text(context.state.startDate, style: .timer)
                        .monospacedDigit()
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.8)
                        .foregroundColor(accentColor)
                        .frame(width: 48, alignment: .trailing)
                } else {
                    Text("--:--")
                        .monospacedDigit()
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            } minimal: {
                // MARK: - Minimal Presentation
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            .keylineTint(accentColor)
            .widgetURL(SleepActivityAttributes.lockScreenWidgetURL)
        }
    }
}

// MARK: - Quick Action Button (Lock Screen & Expanded Dynamic Island)
private struct SleepActivityActionButton: View {
    let isSleeping: Bool

    var body: some View {
        if isSleeping {
            Button(intent: LiveActivityRecordWakeIntent()) {
                buttonLabel(
                    title: "Se despertó",
                    icon: "sun.max.fill",
                    foreground: .black,
                    background: .orange
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
        } else {
            Button(intent: LiveActivityRecordSleepIntent()) {
                buttonLabel(
                    title: "Se durmió",
                    icon: "moon.fill",
                    foreground: .white,
                    background: .indigo
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private func buttonLabel(
        title: String,
        icon: String,
        foreground: Color,
        background: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(background)
        .clipShape(Capsule())
    }
}

// MARK: - Persistent Interactive Presentation for Lock Screen / Banner
public struct SleepActivityCompactView: View {
    let context: ActivityViewContext<SleepActivityAttributes>

    private var isSleeping: Bool {
        context.state.isSleeping
    }

    private var badgeColor: Color {
        isSleeping ? Color.indigo : Color.orange
    }

    private var timerColor: Color {
        isSleeping ? Color(red: 0.62, green: 0.60, blue: 1.0) : Color.orange
    }

    public var body: some View {
        HStack(spacing: 12) {
            // State visual indicator
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.24))
                    .frame(width: 40, height: 40)

                Image(systemName: context.state.statusIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(timerColor)
            }

            // State label & live elapsed timer
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.statusTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if context.state.hasStartDate {
                    Text(context.state.startDate, style: .timer)
                        .monospacedDigit()
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(timerColor)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                } else {
                    Text("--:--")
                        .monospacedDigit()
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Quick state-toggle action button (executes without requiring unlock)
            SleepActivityActionButton(isSleeping: isSleeping)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .widgetURL(SleepActivityAttributes.lockScreenWidgetURL)
    }
}
