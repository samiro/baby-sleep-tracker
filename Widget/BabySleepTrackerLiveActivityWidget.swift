import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

public struct BabySleepTrackerLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            // Lock Screen and banner presentation (active only while sleeping)
            SleepActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island Presentation (Long press on Notch)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.indigo)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.babyName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Durmiendo")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.state.startDate, style: .timer)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.indigo)
                        Text("tiempo de sueño")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Desde las \(formattedTime(context.state.startDate))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // One-tap direct action to wake up
                    Button(intent: RecordWakeIntent()) {
                        HStack(spacing: 6) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Despertó")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundColor(.black)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                // MARK: - Notch Left Wing: Icon (Durmiendo)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.indigo)
                    .padding(.leading, 4)
            } compactTrailing: {
                // MARK: - Notch Right Wing: Time Lapsed (Timer)
                Text(context.state.startDate, style: .timer)
                    .monospacedDigit()
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.indigo)
                    .frame(minWidth: 40, alignment: .trailing)
                    .padding(.trailing, 4)
            } minimal: {
                // MARK: - Minimal Presentation
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.indigo)
            }
            .keylineTint(Color.indigo)
            .widgetURL(URL(string: "emanuelsleep://history"))
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Lock Screen Banner View
public struct SleepActivityLockScreenView: View {
    let context: ActivityViewContext<SleepActivityAttributes>

    public var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                // Left: State Icon
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.indigo)
                }

                // Center: Status & Baby Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.babyName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Durmiendo")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Desde las \(formattedTime(context.state.startDate))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Right: Live Lapsed Timer
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.startDate, style: .timer)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.indigo)
                    Text("tiempo de sueño")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Bottom: One-Tap "Despertó" Button
            Button(intent: RecordWakeIntent()) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Despertó")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundColor(.black)
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.all, 14)
        .widgetURL(URL(string: "emanuelsleep://history"))
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
