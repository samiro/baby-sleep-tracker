import SwiftUI

public struct DailyMetricsCardView: View {
    let metrics: DayMetrics

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    public init(metrics: DayMetrics) {
        self.metrics = metrics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resumen del día")
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Metric 1: Morning wake
                MetricCell(
                    icon: "sunrise.fill",
                    color: .orange,
                    title: "Despertar matutino",
                    value: metrics.morningWakeTime.map { timeFormatter.string(from: $0) } ?? "--:--"
                )

                // Metric 2: Completed naps
                MetricCell(
                    icon: "sun.haze.fill",
                    color: .yellow,
                    title: "Siestas del día",
                    value: "\(metrics.completedNapsCount) siestas"
                )

                // Metric 3: Total Daytime sleep
                MetricCell(
                    icon: "clock.badge.checkmark",
                    color: .blue,
                    title: "Sueño diurno total",
                    value: DayMetrics.formatDuration(metrics.totalDaytimeSleepDuration)
                )

                // Metric 4: Night sleep onset
                MetricCell(
                    icon: "moon.fill",
                    color: .indigo,
                    title: "Inicio sueño nocturno",
                    value: metrics.nightSleepOnset.map { timeFormatter.string(from: $0) } ?? "--:--"
                )

                // Metric 5: Routine start
                MetricCell(
                    icon: "book.closed.fill",
                    color: .purple,
                    title: "Inicio de rutina",
                    value: metrics.bedtimeRoutineStart.map { timeFormatter.string(from: $0) } ?? "--:--"
                )

                // Metric 6: Routine to sleep latency
                MetricCell(
                    icon: "hourglass",
                    color: .teal,
                    title: "Rutina a sueño",
                    value: metrics.routineToSleepDuration.map { DayMetrics.formatDuration($0) } ?? "--:--"
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
