import SwiftUI
import Charts

public struct MetricsAnalyticsView: View {
    private let onSelectHistoryDate: ((Date) -> Void)?
    private let onSelectIncompleteEvent: ((ExcludedIncompleteEvent) -> Void)?

    @State private var selectedPreset: AnalyticsDateRangePreset = .last7Days
    @State private var customStartDate: Date = Date()
    @State private var customEndDate: Date = Date()
    @State private var showCustomRangeSheet = false
    @State private var showIncompleteEventsSheet = false

    @State private var report: SleepAnalyticsReport?
    @State private var selectedCycleId: Date? = nil
    @State private var activeConfig: SleepScheduleConfiguration = SleepConfigurationManager.shared.configuration

    public init(
        onSelectHistoryDate: ((Date) -> Void)? = nil,
        onSelectIncompleteEvent: ((ExcludedIncompleteEvent) -> Void)? = nil
    ) {
        self.onSelectHistoryDate = onSelectHistoryDate
        self.onSelectIncompleteEvent = onSelectIncompleteEvent
    }

    private var selectedCycleSummary: AnalyticsCycleSummary? {
        guard let selectedCycleId, let report else { return nil }
        return report.cycles.first { $0.id == selectedCycleId }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned Date / Cycle Range Selector Header
                pinnedRangeHeader

                Divider()

                // Scrollable Analytics Content
                ScrollView {
                    VStack(spacing: 16) {
                        if let report {
                            if report.isEmpty {
                                emptyStateView(report: report)
                            } else {
                                stackedEvolutionChartCard(report: report)
                                durationMetricsCard(report: report)
                                scheduleConsistencyCard(report: report)
                                dataIntegrityFootnote(report: report)
                            }
                        } else {
                            ProgressView("Calculando métricas...")
                                .padding(.top, 48)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Métricas")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCustomRangeSheet) {
                CustomCycleRangeSheet(
                    startDate: $customStartDate,
                    endDate: $customEndDate,
                    configuration: activeConfig,
                    onApply: {
                        selectedPreset = .custom
                        selectedCycleId = nil
                        reloadReport()
                    }
                )
            }
            .sheet(isPresented: $showIncompleteEventsSheet) {
                if let report {
                    ExcludedIncompleteEventsSheet(
                        events: report.realIncompleteEvents,
                        onSelect: { excluded in
                            showIncompleteEventsSheet = false
                            navigateToIncompleteEvent(excluded)
                        }
                    )
                }
            }
            .onAppear {
                initializeCustomDatesIfNeeded()
                reloadReport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sleepEventsDidChange)) { _ in
                reloadReport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sleepConfigurationDidChange)) { _ in
                reloadReport()
            }
        }
    }

    // MARK: - Pinned Range Selector Header

    private var pinnedRangeHeader: some View {
        VStack(spacing: 10) {
            // Preset selector pills
            HStack(spacing: 6) {
                ForEach(AnalyticsDateRangePreset.allCases) { preset in
                    let isSelected = selectedPreset == preset
                    Button {
                        handlePresetSelection(preset)
                    } label: {
                        Text(preset.shortTitle)
                            .font(.caption)
                            .fontWeight(isSelected ? .bold : .medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .foregroundColor(isSelected ? .white : .primary)
                            .background(
                                isSelected
                                    ? Color.indigo
                                    : Color(.secondarySystemBackground)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Exact cycle window banner + custom edit trigger
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundColor(.indigo)

                VStack(alignment: .leading, spacing: 2) {
                    if let report {
                        Text(report.formattedCycleRangeHeader())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(cycleCoverageSubtitle(for: report))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ciclos de 24 horas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if selectedPreset == .custom {
                    Button {
                        showCustomRangeSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Editar")
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundColor(.indigo)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func cycleCoverageSubtitle(for report: SleepAnalyticsReport) -> String {
        let cycleLabel = "Ciclo 24h (\(report.configuration.nightStartTimeString)–\(report.configuration.dayStartTimeString))"
        if report.activeCyclesCount == 0 {
            return "\(report.totalCyclesCount) ciclos · Sin registros completos"
        } else if report.emptyCyclesCount > 0 {
            return "\(report.activeCyclesCount) de \(report.totalCyclesCount) ciclos con datos · \(cycleLabel)"
        } else {
            return "\(report.totalCyclesCount) ciclos evaluados · \(cycleLabel)"
        }
    }

    // MARK: - Stacked Bar Chart Card

    private func stackedEvolutionChartCard(report: SleepAnalyticsReport) -> some View {
        let maxCycleHours = max(
            report.cycles.map(\.totalSleepHours).max() ?? 0,
            (report.averageTotalSleepDuration ?? 0) / 3600.0
        )
        let yAxisUpper = max(4.0, ceil(maxCycleHours / 2.0) * 2.0 + 1.0)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Distribución diaria entre sueño nocturno y diurno")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.caption2)
                    Text("Toca una barra para ver el detalle")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            if let avg = report.averageTotalSleepDuration {
                HStack(spacing: 8) {
                    Text("Media de sueño total por ciclo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Text(DayMetrics.formatDuration(avg))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundColor(.indigo)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Selected cycle callout (if user taps/scrubs a bar)
            if let inspected = selectedCycleSummary {
                inspectedCycleBanner(inspected)
            }

            // Stacked Bar Chart
            let entries = buildChartEntries(from: report.cycles)
            Chart {
                ForEach(entries) { entry in
                    BarMark(
                        x: .value("Ciclo", entry.axisDay, unit: .day),
                        y: .value("Horas", entry.hours)
                    )
                    .foregroundStyle(by: .value("Tipo", entry.category.rawValue))
                    .cornerRadius(4)
                    .opacity(selectedCycleId == nil || selectedCycleId == entry.cycleStart ? 1.0 : 0.45)
                }

                if let avgTotal = report.averageTotalSleepDuration, avgTotal > 0 {
                    RuleMark(y: .value("Promedio", avgTotal / 3600.0))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                }
            }
            .chartForegroundStyleScale([
                ChartSleepCategory.night.rawValue: Color.indigo,
                ChartSleepCategory.day.rawValue: Color.orange
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: 0...yAxisUpper)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(Int(hours))h")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisTickDates(for: report.cycles)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(shortAxisLabel(for: date, totalCycles: report.cycles.count))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geometry[plotFrame].origin
                            let relativeX = location.x - origin.x
                            guard let tappedDate: Date = proxy.value(atX: relativeX) else { return }
                            selectNearestCycle(to: tappedDate, in: report.cycles)
                        }
                }
            }
            .frame(height: 210)

            // Custom Legend
            HStack(spacing: 14) {
                legendDot(color: .indigo, label: "Nocturno")
                legendDot(color: .orange, label: "Diurno (siestas)")

                if report.averageTotalSleepDuration != nil {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.65))
                            .frame(width: 12, height: 1.5)
                        Text("Media")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func inspectedCycleBanner(_ summary: AnalyticsCycleSummary) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ciclo \(summary.cycle.formattedRangeLabel())")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if summary.hasCompletedSleepData {
                    Text("Total \(DayMetrics.formatDuration(summary.totalSleepDuration)) · Noche \(DayMetrics.formatDuration(summary.nightSleepDuration)) · Día \(DayMetrics.formatDuration(summary.daytimeSleepDuration))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Sin bloques completos registrados en este ciclo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Button("Limpiar") {
                selectedCycleId = nil
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.indigo)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.indigo.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Category 1: Duration Averages & Night Record

    private func durationMetricsCard(report: SleepAnalyticsReport) -> some View {
        let twoColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Duración promedio del sueño",
                icon: "clock.fill",
                color: .indigo
            )

            LazyVGrid(columns: twoColumns, spacing: 10) {
                // Caja 1: Promedio sueño nocturno (same icon & color as 4x2 widget total sleep)
                AnalyticsMetricTile(
                    icon: MediumWidgetSnapshot.nightSleepIconName,
                    color: .indigo,
                    title: "Promedio sueño nocturno",
                    value: report.averageNightSleepDuration.map(DayMetrics.formatDuration) ?? "--",
                    subtitle: nil
                )

                // Caja 2: Promedio sueño diurno (same icon & color as 4x2 widget total sleep)
                AnalyticsMetricTile(
                    title: "Promedio sueño diurno",
                    value: report.averageDaytimeSleepDuration.map(DayMetrics.formatDuration) ?? "--",
                    subtitle: nil
                ) {
                    DaytimeSleepWidgetBadgeIcon()
                }

                // Caja 3: Sueño total promedio por ciclo 24h
                AnalyticsMetricTile(
                    title: "Sueño total promedio por ciclo 24h",
                    value: report.averageTotalSleepDuration.map(DayMetrics.formatDuration) ?? "--",
                    subtitle: nil
                ) {
                    CycleDayNightBadgeIcon()
                }

                // Caja 4: Promedio de siestas (cantidad y duración en el mismo nivel de jerarquía)
                NapAverageMetricTile(
                    averageCountText: SleepAnalyticsReport.formatFrequency(report.averageNapsPerDay),
                    averageDurationText: report.averageNapDuration.map(DayMetrics.formatDuration) ?? "--"
                )
            }

            // Subtle, slim full-width night record tile (2 text lines, no daytime record)
            SubtleNightRecordTile(record: report.longestNightStretch) { record in
                onSelectHistoryDate?(record.startTime)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Category 2: Schedules

    private func scheduleConsistencyCard(report: SleepAnalyticsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Horarios",
                icon: "clock.arrow.2.circlepath",
                color: .purple
            )

            VStack(spacing: 10) {
                ScheduleTrendRow(
                    icon: "moon.fill",
                    color: .indigo,
                    title: "Hora de dormir",
                    average: report.averageNightSleepOnset
                )

                ScheduleTrendRow(
                    icon: "sunrise.fill",
                    color: .orange,
                    title: "Hora despertar matutino",
                    average: report.averageMorningWakeTime
                )

                WakeWindowSummaryCard(
                    averageDaytimeWakingsPerCycle: report.averageDaytimeWakingsPerCycle,
                    averageDaytimeWakeWindow: report.averageDaytimeWakeWindow,
                    averageNightWakingsPerCycle: report.averageNightWakingsPerCycle,
                    averageNightWakingDuration: report.averageNightWakingDuration
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Empty State & Footnote

    private func emptyStateView(report: SleepAnalyticsReport) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 46, weight: .semibold))
                .foregroundColor(.indigo.opacity(0.75))
                .padding(18)
                .background(Color.indigo.opacity(0.10))
                .clipShape(Circle())

            Text("Sin datos suficientes en este periodo")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("No hay bloques de sueño completos (Se durmió → Se despertó) dentro de los ciclos seleccionados para calcular estadísticas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            let realIncomplete = report.realIncompleteEvents
            if !realIncomplete.isEmpty {
                Button {
                    handleRealIncompleteEventsTap(report: report)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                        Text(
                            realIncomplete.count == 1
                                ? "Se excluyó 1 evento incompleto."
                                : "Se excluyeron \(realIncomplete.count) eventos incompletos."
                        )
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .underline()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let ongoingEvent = report.ongoingExcludedEvent {
                Button {
                    navigateToIncompleteEvent(ongoingEvent)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.indigo)
                        Text("No se tiene en cuenta el evento actual.")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .underline()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.indigo)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.indigo.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if selectedPreset != .last30Days {
                    Button {
                        handlePresetSelection(.last30Days)
                    } label: {
                        Text("Ver último mes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .foregroundColor(.white)
                            .background(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showCustomRangeSheet = true
                } label: {
                    Text("Elegir rango")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(.indigo)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func dataIntegrityFootnote(report: SleepAnalyticsReport) -> some View {
        let realIncomplete = report.realIncompleteEvents
        let ongoingEvent = report.ongoingExcludedEvent

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(baseFootnoteText(for: report))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !realIncomplete.isEmpty {
                        Button {
                            handleRealIncompleteEventsTap(report: report)
                        } label: {
                            HStack(spacing: 4) {
                                Text(incompleteEventsLinkText(count: realIncomplete.count))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .underline()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.indigo)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Abre el ciclo correspondiente en el historial para revisar el evento incompleto excluido.")
                    }

                    if let ongoingEvent {
                        Button {
                            navigateToIncompleteEvent(ongoingEvent)
                        } label: {
                            HStack(spacing: 4) {
                                Text("No se tiene en cuenta el evento actual")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .underline()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.indigo)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Abre el evento en curso en el historial.")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func baseFootnoteText(for report: SleepAnalyticsReport) -> String {
        var parts: [String] = [
            "Calculado solo con bloques completos (Se durmió → Se despertó) bajo el ciclo 24h configurado (\(report.configuration.nightStartTimeString)–\(report.configuration.dayStartTimeString))."
        ]
        if report.emptyCyclesCount > 0 {
            let suffix = report.emptyCyclesCount == 1 ? "ciclo sin registros fue excluido" : "ciclos sin registros fueron excluidos"
            parts.append("\(report.emptyCyclesCount) \(suffix) de los promedios.")
        }
        return parts.joined(separator: " ")
    }

    private func incompleteEventsLinkText(count: Int) -> String {
        let suffix = count == 1 ? "evento incompleto excluido" : "eventos incompletos excluidos"
        return "\(count) \(suffix)"
    }

    private func handleRealIncompleteEventsTap(report: SleepAnalyticsReport) {
        let excluded = report.realIncompleteEvents
        guard let first = excluded.first else { return }

        if excluded.count == 1 {
            navigateToIncompleteEvent(first)
            return
        }

        let distinctCycleStarts = Set(
            excluded.map { report.configuration.cycleRange(containing: $0.timestamp).start }
        )
        if distinctCycleStarts.count <= 1 {
            navigateToIncompleteEvent(first)
        } else {
            showIncompleteEventsSheet = true
        }
    }

    private func navigateToIncompleteEvent(_ excluded: ExcludedIncompleteEvent) {
        if let onSelectIncompleteEvent {
            onSelectIncompleteEvent(excluded)
        } else {
            onSelectHistoryDate?(excluded.timestamp)
        }
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    // MARK: - Chart Helpers

    private enum ChartSleepCategory: String, CaseIterable {
        case night = "Nocturno"
        case day = "Diurno"
    }

    private struct ChartSleepEntry: Identifiable {
        let id: String
        let cycleStart: Date
        let axisDay: Date
        let category: ChartSleepCategory
        let hours: Double
    }

    private func buildChartEntries(from cycles: [AnalyticsCycleSummary]) -> [ChartSleepEntry] {
        let calendar = Calendar.current
        var entries: [ChartSleepEntry] = []
        entries.reserveCapacity(cycles.count * 2)
        for cycle in cycles {
            let baseId = "\(Int(cycle.cycle.start.timeIntervalSince1970))"
            let axisDay = calendar.startOfDay(for: cycle.cycle.start)
            entries.append(
                ChartSleepEntry(
                    id: "\(baseId)-night",
                    cycleStart: cycle.cycle.start,
                    axisDay: axisDay,
                    category: .night,
                    hours: cycle.nightSleepHours
                )
            )
            entries.append(
                ChartSleepEntry(
                    id: "\(baseId)-day",
                    cycleStart: cycle.cycle.start,
                    axisDay: axisDay,
                    category: .day,
                    hours: cycle.daytimeSleepHours
                )
            )
        }
        return entries
    }

    private func axisTickDates(for cycles: [AnalyticsCycleSummary]) -> [Date] {
        guard !cycles.isEmpty else { return [] }
        let calendar = Calendar.current
        let axisDays = cycles.map { calendar.startOfDay(for: $0.cycle.start) }
        let count = axisDays.count
        if count <= 7 {
            return axisDays
        }
        let targetTicks = 5
        let strideStep = max(1, (count - 1) / (targetTicks - 1))
        var ticks: [Date] = []
        var idx = 0
        while idx < count {
            ticks.append(axisDays[idx])
            idx += strideStep
        }
        if let last = axisDays.last, ticks.last != last {
            if ticks.count >= 2 {
                ticks[ticks.count - 1] = last
            } else {
                ticks.append(last)
            }
        }
        return ticks
    }

    private func shortAxisLabel(for date: Date, totalCycles: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = totalCycles <= 7 ? "d MMM" : "d/M"
        return formatter.string(from: date)
    }

    private func selectNearestCycle(to tappedDate: Date, in cycles: [AnalyticsCycleSummary]) {
        let calendar = Calendar.current
        let tappedDay = calendar.startOfDay(for: tappedDate)
        let matched = cycles.first {
            calendar.isDate($0.cycle.start, inSameDayAs: tappedDay)
        } ?? cycles.min(by: {
            abs(calendar.startOfDay(for: $0.cycle.start).timeIntervalSince(tappedDay))
                < abs(calendar.startOfDay(for: $1.cycle.start).timeIntervalSince(tappedDay))
        })
        guard let matched else { return }
        if selectedCycleId == matched.id {
            selectedCycleId = nil
        } else {
            selectedCycleId = matched.id
        }
    }

    // MARK: - Actions & Data Loading

    private func initializeCustomDatesIfNeeded() {
        let config = SleepConfigurationManager.shared.configuration
        activeConfig = config
        if report == nil {
            let currentCycle = config.cycleRange(offset: 0)
            let weekAgoCycle = config.cycleRange(offset: -6)
            customStartDate = weekAgoCycle.start
            customEndDate = currentCycle.start
        }
    }

    private func handlePresetSelection(_ preset: AnalyticsDateRangePreset) {
        if preset == .custom {
            if selectedPreset != .custom, let first = report?.cycles.first?.cycle.start, let last = report?.cycles.last?.cycle.start {
                customStartDate = first
                customEndDate = last
            }
            showCustomRangeSheet = true
        } else {
            selectedPreset = preset
            selectedCycleId = nil
            reloadReport()
        }
    }

    private func reloadReport() {
        let config = SleepConfigurationManager.shared.configuration
        activeConfig = config
        report = try? SleepAnalyticsService.shared.generateReport(
            preset: selectedPreset,
            customStartDate: selectedPreset == .custom ? customStartDate : nil,
            customEndDate: selectedPreset == .custom ? customEndDate : nil,
            configuration: config
        )
        if let selectedCycleId, let report, !report.cycles.contains(where: { $0.id == selectedCycleId }) {
            self.selectedCycleId = nil
        }
    }
}

// MARK: - Reusable Subviews

private struct StandardMetricBadgeIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(color)
            .frame(width: 26, height: 26)
            .background(color.opacity(0.15))
            .clipShape(Circle())
    }
}

private struct DaytimeSleepWidgetBadgeIcon: View {
    private static let daytimeSleepColor = Color(red: 0.78, green: 0.56, blue: 0.04)

    var body: some View {
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
        .frame(width: 26, height: 26)
        .background(Self.daytimeSleepColor.opacity(0.15))
        .clipShape(Circle())
    }
}

private struct CycleDayNightBadgeIcon: View {
    private static let daytimeSleepColor = Color(red: 0.78, green: 0.56, blue: 0.04)

    var body: some View {
        ZStack {
            Image(systemName: "moon.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.indigo)
                .offset(x: -4, y: -3.5)

            Image(systemName: "sun.max.fill")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Self.daytimeSleepColor)
                .offset(x: 4, y: 3.5)
        }
        .frame(width: 26, height: 26)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.16), Self.daytimeSleepColor.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Circle())
    }
}

private struct AnalyticsMetricTile<IconContent: View>: View {
    let title: String
    let value: String
    let subtitle: String?
    let iconContent: IconContent

    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        @ViewBuilder icon: () -> IconContent
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.iconContent = icon()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                iconContent

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension AnalyticsMetricTile where IconContent == StandardMetricBadgeIcon {
    init(
        icon: String,
        color: Color,
        title: String,
        value: String,
        subtitle: String? = nil
    ) {
        self.init(title: title, value: value, subtitle: subtitle) {
            StandardMetricBadgeIcon(icon: icon, color: color)
        }
    }
}

private struct NapAverageMetricTile: View {
    let averageCountText: String
    let averageDurationText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StandardMetricBadgeIcon(icon: "timer", color: .teal)

                Text("Promedio de siestas")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(averageCountText)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("por día")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 28)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(averageDurationText)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("duración")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SubtleNightRecordTile: View {
    let record: SleepDurationRecord?
    let onSelect: (SleepDurationRecord) -> Void

    var body: some View {
        if let record {
            Button {
                onSelect(record)
            } label: {
                tileContent(record: record)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Récord nocturno \(record.formattedDuration), \(record.formattedDateLabel())")
            .accessibilityHint("Abre el historial correspondiente a esta fecha")
        } else {
            tileContent(record: nil)
        }
    }

    private func tileContent(record: SleepDurationRecord?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.indigo.opacity(0.75))

            VStack(alignment: .leading, spacing: 2) {
                Text("Récord nocturno")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(record.map { "Registrado el \($0.formattedDateLabel())" } ?? "Sin registros")
                    .font(.caption2)
                    .foregroundStyle(record != nil ? Color.indigo.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Text(record?.formattedDuration ?? "--")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)

                if record != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.indigo.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct ScheduleTrendRow: View {
    let icon: String
    let color: Color
    let title: String
    let average: TimeOfDayAverage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.15))
                    .clipShape(Circle())

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let average {
                WeightedHStack(weights: [0.26, 0.30, 0.44], spacing: 6) {
                    ScheduleMetricCell(
                        label: "Promedio",
                        value: average.formattedAverageTime,
                        tint: color
                    )

                    ScheduleMetricCell(
                        label: "Variación",
                        value: average.formattedVariation,
                        tint: color
                    )

                    ScheduleMetricCell(
                        label: "Rango",
                        value: average.sampleCount > 1 ? average.formattedMinMaxRange : "—",
                        tint: color
                    )
                }
            } else {
                Text("Sin registros en este periodo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ScheduleMetricCell: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct WakeWindowSummaryCard: View {
    let averageDaytimeWakingsPerCycle: Double?
    let averageDaytimeWakeWindow: TimeInterval?
    let averageNightWakingsPerCycle: Double?
    let averageNightWakingDuration: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sun.haze.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.teal)
                    .frame(width: 26, height: 26)
                    .background(Color.teal.opacity(0.15))
                    .clipShape(Circle())

                Text("Ventana de vigilia promedio")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 8) {
                WakePeriodGroupRow(
                    periodTitle: "Despertares diurnos",
                    icon: "sun.max.fill",
                    accentColor: .orange,
                    countLabel: "Cantidad promedio día",
                    countValue: SleepAnalyticsReport.formatFrequency(averageDaytimeWakingsPerCycle),
                    durationLabel: "Duración promedio",
                    durationValue: averageDaytimeWakeWindow.map(DayMetrics.formatDuration) ?? "--"
                )

                WakePeriodGroupRow(
                    periodTitle: "Despertares nocturnos",
                    icon: "moon.stars.fill",
                    accentColor: .indigo,
                    countLabel: "Cantidad promedio noche",
                    countValue: SleepAnalyticsReport.formatFrequency(averageNightWakingsPerCycle),
                    durationLabel: "Duración promedio",
                    durationValue: averageNightWakingDuration.map(DayMetrics.formatDuration) ?? "--"
                )
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WakePeriodGroupRow: View {
    let periodTitle: String
    let icon: String
    let accentColor: Color
    let countLabel: String
    let countValue: String
    let durationLabel: String
    let durationValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accentColor)

                Text(periodTitle)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(accentColor)

                Spacer()
            }

            WeightedHStack(weights: [0.55, 0.45], spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(countLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(countValue)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 1, height: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(durationLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(durationValue)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WeightedHStack: Layout {
    let weights: [CGFloat]
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let totalWidth = proposal.width ?? 300
        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let availableWidth = max(0, totalWidth - totalSpacing)
        let totalWeight = weights.prefix(subviews.count).reduce(0, +)
        var maxHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let weight = index < weights.count ? weights[index] : 1
            let width = totalWeight > 0 ? availableWidth * (weight / totalWeight) : 0
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
            maxHeight = max(maxHeight, size.height)
        }

        return CGSize(width: totalWidth, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let availableWidth = max(0, bounds.width - totalSpacing)
        let totalWeight = weights.prefix(subviews.count).reduce(0, +)
        var x = bounds.minX

        for (index, subview) in subviews.enumerated() {
            let weight = index < weights.count ? weights[index] : 1
            let width = totalWeight > 0 ? availableWidth * (weight / totalWeight) : 0
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}

// MARK: - Excluded Incomplete Events Sheet

private struct ExcludedIncompleteEventsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let events: [ExcludedIncompleteEvent]
    let onSelect: (ExcludedIncompleteEvent) -> Void

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(events) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                let isOngoing = item.reason.isOngoing
                                Image(systemName: isOngoing ? item.event.type.iconName : "exclamationmark.triangle.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(isOngoing ? .green : .orange)
                                    .frame(width: 30, height: 30)
                                    .background((isOngoing ? Color.green : Color.orange).opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.event.type.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)

                                        Text(item.reason.badgeTitle)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background((isOngoing ? Color.green : Color.orange).opacity(0.18))
                                            .foregroundColor(isOngoing ? .green : .orange)
                                            .clipShape(Capsule())
                                    }

                                    Text(Self.dateTimeFormatter.string(from: item.timestamp))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)

                                    if let explanation = item.reason.explanationMessage {
                                        Text(explanation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Selecciona un evento para abrir su ciclo en el historial")
                }
            }
            .navigationTitle("Eventos excluidos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Custom Cycle Range Picker Sheet

private struct CustomCycleRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var startDate: Date
    @Binding var endDate: Date
    let configuration: SleepScheduleConfiguration
    let onApply: () -> Void

    @State private var draftStart: Date = Date()
    @State private var draftEnd: Date = Date()

    private var maxSelectableDate: Date {
        let startOfCurrentCycleDay = Calendar.current.startOfDay(for: configuration.cycleRange(offset: 0).start)
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: startOfCurrentCycleDay)
            ?? configuration.cycleRange(offset: 0).start
    }

    private var previewCycles: [SleepCycleRange] {
        SleepAnalyticsService.shared.resolveCycles(
            preset: .custom,
            customStartDate: draftStart,
            customEndDate: draftEnd,
            configuration: configuration
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Ciclo de inicio",
                        selection: $draftStart,
                        in: ...maxSelectableDate,
                        displayedComponents: [.date]
                    )

                    DatePicker(
                        "Ciclo de fin",
                        selection: $draftEnd,
                        in: draftStart...maxSelectableDate,
                        displayedComponents: [.date]
                    )
                } header: {
                    Text("Selecciona las fechas del rango")
                } footer: {
                    Text("Cada fecha representa un ciclo completo de 24 horas alineado con el horario configurado en Ajustes (\(configuration.nightStartTimeString) – \(configuration.dayStartTimeString)).")
                        .font(.caption)
                }

                if let first = previewCycles.first, let last = previewCycles.last {
                    Section("Resumen del rango") {
                        HStack {
                            Text("Inicio exacto")
                            Spacer()
                            Text(formattedDateTime(first.start))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Fin exacto")
                            Spacer()
                            Text(formattedDateTime(last.displayEnd))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Ciclos incluidos")
                            Spacer()
                            Text("\(previewCycles.count) \(previewCycles.count == 1 ? "ciclo" : "ciclos") (24h)")
                                .fontWeight(.semibold)
                                .foregroundColor(.indigo)
                        }
                    }
                }
            }
            .navigationTitle("Rango personalizado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        startDate = min(draftStart, draftEnd)
                        endDate = max(draftStart, draftEnd)
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let clampedEnd = min(endDate, maxSelectableDate)
                let clampedStart = min(startDate, clampedEnd)
                draftStart = clampedStart
                draftEnd = clampedEnd
            }
            .onChange(of: draftStart) { _, newValue in
                if newValue > draftEnd {
                    draftEnd = newValue
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}
