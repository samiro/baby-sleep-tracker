import SwiftUI
import WidgetKit
import AppIntents

public struct EmanuelSleepWidgetMediumView: View {
    let entry: SleepWidgetEntry

    public init(entry: SleepWidgetEntry) {
        self.entry = entry
    }

    private var snapshot: MediumWidgetSnapshot {
        entry.snapshot
    }

    private var stateColor: Color {
        switch snapshot.state {
        case .sleeping:
            return .indigo
        case .awake:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    public var body: some View {
        HStack(spacing: 12) {
            // MARK: - Block 1: Current State & Single Dynamic Action
            VStack(alignment: .leading, spacing: 6) {
                // Dynamic baby / app identity
                Text(snapshot.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Current state pill
                HStack(spacing: 5) {
                    Image(systemName: snapshot.stateIconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(stateColor)
                    Text(snapshot.stateTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(stateColor)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(stateColor.opacity(0.15))
                .clipShape(Capsule())

                // Elapsed live timer (no redundant state subtitle)
                if let since = snapshot.state.sinceDate {
                    Text(since, style: .timer)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                } else {
                    Text("--:--")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 2)

                // Single dynamic primary action button
                primaryActionButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 2)

            // MARK: - Block 2: Current 24-Hour Cycle Summary
            VStack(alignment: .leading, spacing: 10) {
                // Active 24h cycle window label
                Text(snapshot.formattedCycleWindow())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Last recorded event (exact time + event type)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Último evento")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let timeText = snapshot.formattedLastEventTime(),
                       let eventLabel = snapshot.lastEventLabel {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(timeText)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            Text("· \(eventLabel)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    } else {
                        Text("Sin registros")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Total accumulated sleep in current 24h cycle
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sueño del ciclo")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 5) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.indigo)
                        Text(snapshot.formattedCycleTotalSleep)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
            .frame(width: 136, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, 2)
        .widgetURL(MediumWidgetSnapshot.widgetURL)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch snapshot.primaryAction {
        case .recordWake:
            Button(intent: RecordWakeIntent()) {
                actionButtonLabel(
                    title: MediumWidgetAction.recordWake.title,
                    icon: MediumWidgetAction.recordWake.iconName,
                    foreground: .black,
                    background: .orange
                )
            }
            .buttonStyle(.plain)

        case .recordSleep:
            Button(intent: RecordSleepIntent()) {
                actionButtonLabel(
                    title: MediumWidgetAction.recordSleep.title,
                    icon: MediumWidgetAction.recordSleep.iconName,
                    foreground: .white,
                    background: .indigo
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButtonLabel(
        title: String,
        icon: String,
        foreground: Color,
        background: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
