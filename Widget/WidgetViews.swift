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

    private var recentEventsTitle: String {
        snapshot.recentCycleEvents.count == 1 ? "Último evento" : "Últimos eventos"
    }

    private static let daytimeSleepColor = Color(red: 0.78, green: 0.56, blue: 0.04)

    public var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 10
            let dividerWidth: CGFloat = 1
            let availableWidth = max(0, geometry.size.width - (spacing * 2 + dividerWidth))
            let leftWidth = availableWidth * 0.40
            let rightWidth = availableWidth * 0.60

            HStack(spacing: spacing) {
                // MARK: - Block 1 (40%): Identity, Current State, Live Timer & Action
                VStack(alignment: .center, spacing: 0) {
                    // Dynamic baby / app identity anchored at top
                    Text(snapshot.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 4)

                    // Centered status pill + elapsed live timer group
                    VStack(alignment: .center, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: snapshot.stateIconName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(stateColor)
                            Text(snapshot.stateTitle)
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(stateColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(stateColor.opacity(0.15))
                        .clipShape(Capsule())

                        if let since = snapshot.state.sinceDate {
                            Text(since, style: .timer)
                                .font(.system(size: 21, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text("--:--")
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    Spacer(minLength: 4)

                    // Single dynamic primary action button anchored at bottom
                    primaryActionButton
                }
                .frame(width: leftWidth, height: geometry.size.height, alignment: .center)

                Divider()
                    .frame(width: dividerWidth)
                    .padding(.vertical, 2)

                // MARK: - Block 2 (60%): Current 24-Hour Cycle Summary
                VStack(alignment: .leading, spacing: 8) {
                    // Last 1-2 recorded events in current cycle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recentEventsTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if snapshot.recentCycleEvents.isEmpty {
                            Text("Sin registros")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(snapshot.recentCycleEvents.enumerated()), id: \.element.id) { index, event in
                                    recentEventRow(event: event, isLatest: index == 0)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // Cycle sleep breakdown: Nighttime (left) vs Daytime (right)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sueño total noche y día")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        HStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Image(systemName: MediumWidgetSnapshot.nightSleepIconName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.indigo)
                                Text(snapshot.formattedCycleNightSleep)
                                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Sueño nocturno \(snapshot.formattedCycleNightSleep)")

                            Spacer(minLength: 6)

                            HStack(spacing: 3) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: MediumWidgetSnapshot.daytimeSleepIconName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.trailing, 4)
                                        .padding(.top, 2)
                                    Image(systemName: "zzz")
                                        .font(.system(size: 6.5, weight: .heavy))
                                        .offset(x: 1, y: -1)
                                }
                                .foregroundStyle(Self.daytimeSleepColor)
                                Text(snapshot.formattedCycleDaytimeSleep)
                                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Sueño diurno \(snapshot.formattedCycleDaytimeSleep)")
                        }
                    }
                }
                .frame(width: rightWidth, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .padding(.vertical, 2)
        .widgetURL(MediumWidgetSnapshot.widgetURL)
    }

    private func recentEventRow(event: SleepEvent, isLatest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(MediumWidgetSnapshot.formattedTime(for: event))
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isLatest ? .primary : .secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text("· \(MediumWidgetSnapshot.eventLabel(for: event))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
