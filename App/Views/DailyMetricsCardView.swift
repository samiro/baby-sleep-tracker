import SwiftUI

public struct DailyMetricsCardView: View {
    let metrics: DayMetrics
    let title: String

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    public init(metrics: DayMetrics, title: String = "Resumen") {
        self.metrics = metrics
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Metric 1: Night sleep onset
                MetricCell(
                    icon: "moon.fill",
                    color: .indigo,
                    title: "Inicio sueño nocturno",
                    value: metrics.nightSleepOnset.map { timeFormatter.string(from: $0) } ?? "--:--"
                )

                // Metric 2: Morning wake
                MetricCell(
                    icon: "sunrise.fill",
                    color: .orange,
                    title: "Despertar matutino",
                    value: metrics.morningWakeTime.map { timeFormatter.string(from: $0) } ?? "--:--"
                )

                // Metric 3: Total Night sleep
                MetricCell(
                    icon: "moon.stars.fill",
                    color: .purple,
                    title: "Sueño nocturno total",
                    value: DayMetrics.formatDuration(metrics.totalNightSleepDuration)
                )

                // Metric 4: Completed naps
                MetricCell(
                    icon: "sun.haze.fill",
                    color: .yellow,
                    title: "Siestas del día",
                    value: "\(metrics.completedNapsCount) siestas"
                )

                // Metric 5: Total Daytime sleep
                MetricCell(
                    icon: "clock.badge.checkmark",
                    color: .blue,
                    title: "Sueño diurno total",
                    value: DayMetrics.formatDuration(metrics.totalDaytimeSleepDuration)
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MetricCell: View {
    let icon: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Expanded Cycle Summary Card (History View)

public struct CycleSummaryCardView: View {
    let metrics: DayMetrics
    let configuration: SleepScheduleConfiguration
    let activeOngoingInterval: SleepInterval?
    let title: String

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public init(
        metrics: DayMetrics,
        configuration: SleepScheduleConfiguration = SleepConfigurationManager.shared.configuration,
        activeOngoingInterval: SleepInterval? = nil,
        title: String = "Resumen del ciclo"
    ) {
        self.metrics = metrics
        self.configuration = configuration
        self.activeOngoingInterval = activeOngoingInterval
        self.title = title
    }

    public var body: some View {
        if activeOngoingInterval != nil {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                cardContent(at: context.date)
            }
        } else {
            cardContent(at: Date())
        }
    }

    @ViewBuilder
    private func cardContent(at now: Date) -> some View {
        let nightTotalDuration = metrics.effectiveTotalNightSleepDuration(
            including: activeOngoingInterval,
            at: now
        )
        let daytimeTotalDuration = metrics.effectiveTotalDaytimeSleepDuration(
            including: activeOngoingInterval,
            at: now
        )

        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            // Night Block
            periodBlock(
                title: "Noche",
                windowSubtitle: "\(configuration.nightStartTimeString) – \(configuration.dayStartTimeString)",
                icon: "moon.stars.fill",
                accentColor: .indigo,
                totalDuration: nightTotalDuration,
                totalLabel: "Sueño nocturno"
            ) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 7
                ) {
                    CycleMetricRow(
                        title: "Hora de dormir",
                        value: metrics.nightSleepOnset.map { Self.timeFormatter.string(from: $0) } ?? "--:--",
                        isPlaceholder: metrics.nightSleepOnset == nil
                    )

                    CycleMetricRow(
                        title: "Despertares",
                        value: "\(metrics.nightWakingsCount)",
                        isPlaceholder: false
                    )

                    CycleMetricRow(
                        title: "Sueño más largo",
                        value: DayMetrics.formatOptionalDuration(metrics.longestNightSleepDuration),
                        isPlaceholder: metrics.longestNightSleepDuration == nil
                    )

                    CycleMetricRow(
                        title: "Vigilia más larga",
                        value: DayMetrics.formatOptionalDuration(metrics.longestNightAwakeDuration),
                        isPlaceholder: metrics.longestNightAwakeDuration == nil
                    )
                }
            }

            // Day Block
            periodBlock(
                title: "Día",
                windowSubtitle: "\(configuration.dayStartTimeString) – \(configuration.nightStartTimeString)",
                icon: "sun.max.fill",
                accentColor: .orange,
                totalDuration: daytimeTotalDuration,
                totalLabel: "Sueño diurno"
            ) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 7
                ) {
                    CycleMetricRow(
                        title: "Despertar matutino",
                        value: metrics.morningWakeTime.map { Self.timeFormatter.string(from: $0) } ?? "--:--",
                        isPlaceholder: metrics.morningWakeTime == nil
                    )

                    CycleMetricRow(
                        title: "Siestas",
                        value: "\(metrics.completedNapsCount)",
                        isPlaceholder: false
                    )

                    CycleMetricRow(
                        title: "Siesta más larga",
                        value: DayMetrics.formatOptionalDuration(metrics.longestDaytimeSleepDuration),
                        isPlaceholder: metrics.longestDaytimeSleepDuration == nil
                    )

                    CycleMetricRow(
                        title: "Vigilia más larga",
                        value: DayMetrics.formatOptionalDuration(metrics.longestDaytimeAwakeDuration),
                        isPlaceholder: metrics.longestDaytimeAwakeDuration == nil
                    )
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func periodBlock<Content: View>(
        title: String,
        windowSubtitle: String,
        icon: String,
        accentColor: Color,
        totalDuration: TimeInterval,
        totalLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header with period icon, cycle window, and total period sleep
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 26, height: 26)
                    .background(accentColor.opacity(0.16))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(accentColor)

                    Text(windowSubtitle)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text(DayMetrics.formatDuration(totalDuration))
                        .font(.headline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text(totalLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .overlay(accentColor.opacity(0.16))

            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct CycleMetricRow: View {
    let title: String
    let value: String
    let isPlaceholder: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
