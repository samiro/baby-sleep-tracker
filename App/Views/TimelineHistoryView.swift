import SwiftUI

public struct TimelineHistoryView: View {
    @State private var cycleOffset: Int = 0
    @State private var activeConfig: SleepScheduleConfiguration = SleepConfigurationManager.shared.configuration
    @State private var events: [SleepEvent] = []
    @State private var incompleteEventReasons: [UUID: SleepEventIncompleteReason] = [:]
    @State private var metrics: DayMetrics?
    @State private var activeOngoingInterval: SleepInterval?
    @State private var editingEvent: SleepEvent?
    @State private var isAddingEvent = false
    @State private var eventToDelete: SleepEvent?
    @State private var showDeleteConfirmation = false
    @State private var selectedCrossCycleInfo: CrossCycleIntervalInfo?
    @State private var showCrossCycleAlert = false
    @State private var showExportSheet = false
    @State private var csvExportString: String = ""
    @State private var jsonExportData: Data = Data()
    @State private var isSharePresented = false

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var shortDayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f
    }

    private enum EventTimelineRow: Identifiable {
        case daySeparator(Date, isFirst: Bool)
        case event(SleepEvent)

        var id: String {
            switch self {
            case .daySeparator(let day, _):
                return "day-\(Int(day.timeIntervalSince1970))"
            case .event(let event):
                return event.id.uuidString
            }
        }
    }

    private var eventTimelineRows: [EventTimelineRow] {
        guard !events.isEmpty else { return [] }
        let calendar = Calendar.current
        let distinctDays = Set(events.map { calendar.startOfDay(for: $0.timestamp) })
        let spansMultipleDays = distinctDays.count > 1

        var rows: [EventTimelineRow] = []
        var lastDay: Date? = nil
        for event in events {
            let eventDay = calendar.startOfDay(for: event.timestamp)
            if spansMultipleDays, lastDay != eventDay {
                rows.append(.daySeparator(eventDay, isFirst: lastDay == nil))
                lastDay = eventDay
            }
            rows.append(.event(event))
        }
        return rows
    }

    private var displayedCycle: SleepCycleRange {
        activeConfig.cycleRange(offset: cycleOffset)
    }

    private var initialDateForNewEvent: Date {
        let now = Date()
        if cycleOffset == 0 {
            return now
        }
        let shifted = Calendar.current.date(byAdding: .day, value: cycleOffset, to: now) ?? displayedCycle.start
        return SleepEvent.clampedInitialTimestamp(shifted, now: now)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Group {
                    // Cycle Navigation Bar
                    cycleNavigationBar

                    // Cycle Metrics Summary
                    if let metrics = metrics {
                        DailyMetricsCardView(metrics: metrics, title: "Resumen del ciclo")
                    }

                    // Sleep Intervals Section
                    intervalsSection
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                // Raw Events Timeline Section
                Section {
                    if events.isEmpty {
                        Text("Sin eventos en este ciclo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            .background(Color(.secondarySystemBackground).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(eventTimelineRows) { row in
                            switch row {
                            case .daySeparator(let day, let isFirst):
                                daySeparatorRow(for: day)
                                    .listRowInsets(EdgeInsets(top: isFirst ? 2 : 10, leading: 20, bottom: 2, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            case .event(let event):
                                Button {
                                    editingEvent = event
                                } label: {
                                    eventRow(for: event)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        eventToDelete = event
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Registro de eventos")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 10)
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            exportData(format: .csv)
                        } label: {
                            Label("Exportar como CSV", systemImage: "doc.text")
                        }

                        Button {
                            exportData(format: .json)
                        } label: {
                            Label("Exportar como JSON", systemImage: "curlybraces")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingEvent = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                }
            }
            .sheet(isPresented: $isAddingEvent) {
                AddEditEventView(
                    initialDate: initialDateForNewEvent,
                    onSave: { newEvent in
                        try? SleepTrackingService.shared.recordEvent(
                            type: newEvent.type,
                            timestamp: newEvent.timestamp,
                            classification: newEvent.classification,
                            notes: newEvent.notes,
                            force: true
                        )
                        reloadData()
                    }
                )
            }
            .sheet(item: $editingEvent) { event in
                AddEditEventView(
                    existingEvent: event,
                    onSave: { updated in
                        try? SleepTrackingService.shared.updateEvent(updated)
                        reloadData()
                    },
                    onDelete: { id in
                        try? SleepTrackingService.shared.deleteEvent(id: id)
                        reloadData()
                    }
                )
            }
            .confirmationDialog(
                "¿Eliminar evento?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    if let ev = eventToDelete {
                        try? SleepTrackingService.shared.deleteEvent(id: ev.id)
                        reloadData()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción eliminará el evento seleccionado de forma irreversible.")
            }
            .alert("Intervalo entre ciclos", isPresented: $showCrossCycleAlert, presenting: selectedCrossCycleInfo) { _ in
                Button("Entendido", role: .cancel) {}
            } message: { info in
                Text(info.detailMessage())
            }
            .sheet(isPresented: $isSharePresented) {
                ShareSheet(items: shareItems)
            }
            .onAppear {
                reloadData()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sleepEventsDidChange)) { _ in
                reloadData()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sleepConfigurationDidChange)) { _ in
                reloadData()
            }
        }
    }

    // MARK: - Components

    private var cycleNavigationBar: some View {
        let cycle = displayedCycle
        return HStack {
            Button {
                changeCycle(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Ciclo anterior")

            Spacer()

            VStack(spacing: 2) {
                Text(cycle.navigationTitle(forOffset: cycleOffset))
                    .font(.headline)
                Text(cycle.navigationSubtitle(forOffset: cycleOffset))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                changeCycle(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
                    .opacity(canNavigateToNextCycle ? 1.0 : 0.35)
            }
            .buttonStyle(.borderless)
            .disabled(!canNavigateToNextCycle)
            .accessibilityLabel("Ciclo siguiente")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private var displayedSleepIntervals: [SleepInterval] {
        var result = metrics?.sleepIntervals ?? []
        if let ongoing = activeOngoingInterval,
           !result.contains(where: { $0.id == ongoing.id }) {
            result.append(ongoing)
        }
        return result.sorted { $0.startTime < $1.startTime }
    }

    private var intervalsSection: some View {
        let intervals = displayedSleepIntervals
        return VStack(alignment: .leading, spacing: 10) {
            Text("Intervalos de sueño")
                .font(.headline)

            if !intervals.isEmpty {
                ForEach(intervals) { interval in
                    let crossCycleInfo = activeConfig.crossCycleInfo(for: interval)
                    if let crossCycleInfo = crossCycleInfo {
                        Button {
                            selectedCrossCycleInfo = crossCycleInfo
                            showCrossCycleAlert = true
                        } label: {
                            intervalCard(for: interval, spansCycles: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        intervalCard(for: interval, spansCycles: false)
                    }
                }
            } else {
                Text("No hay intervalos registrados en este ciclo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func intervalCard(for interval: SleepInterval, spansCycles: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: interval.classification == .nap ? "sun.haze.fill" : "moon.stars.fill")
                .font(.system(size: 20))
                .foregroundColor(interval.classification == .nap ? .orange : .indigo)
                .frame(width: 36, height: 36)
                .background((interval.classification == .nap ? Color.orange : Color.indigo).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(interval.classification.displayName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    if !interval.isCompleted {
                        Text("En curso")
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }

                if spansCycles {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("Cruza ciclos")
                            .font(.caption2)
                            .fontWeight(.bold)
                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                }

                Text(interval.rangeText(includeDate: spansCycles))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(interval.formattedDuration)
                .font(.subheadline)
                .fontWeight(.heavy)
                .monospacedDigit()
        }
        .padding()
        .background(
            ZStack {
                Color(.secondarySystemBackground)
                if spansCycles {
                    Color.orange.opacity(0.05)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(spansCycles ? Color.orange.opacity(0.55) : Color.clear, lineWidth: 1.2)
        )
    }

    private func daySeparatorRow(for day: Date) -> some View {
        Text(shortDayFormatter.string(from: day))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(for event: SleepEvent) -> some View {
        let incompleteReason = incompleteEventReasons[event.id]
        let isOngoing = incompleteReason?.isOngoing ?? false
        let isWarning = incompleteReason != nil && !isOngoing

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: isWarning ? "exclamationmark.triangle.fill" : event.type.iconName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isWarning ? .orange : colorForEvent(event.type))
                    .frame(width: 32, height: 32)
                    .background((isWarning ? Color.orange : colorForEvent(event.type)).opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if event.type == .sleep {
                            let dynamicClassification = activeConfig.classify(timestamp: event.timestamp)
                            Text("(\(dynamicClassification.displayName))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let reason = incompleteReason {
                            Text(reason.badgeTitle)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isOngoing ? Color.green.opacity(0.2) : Color.orange.opacity(0.18))
                                .foregroundColor(isOngoing ? .green : .orange)
                                .clipShape(Capsule())
                        }
                    }

                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Text(timeFormatter.string(from: event.timestamp))
                    .font(.subheadline)
                    .monospacedDigit()
                    .fontWeight(.medium)
            }

            if let explanation = incompleteReason?.explanationMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 1)
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Color(.secondarySystemBackground)
                if isWarning {
                    Color.orange.opacity(0.06)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isWarning ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Actions

    private var canNavigateToNextCycle: Bool {
        cycleOffset < 0
    }

    private func changeCycle(by offset: Int) {
        let nextOffset = min(0, cycleOffset + offset)
        guard nextOffset != cycleOffset else { return }
        cycleOffset = nextOffset
        reloadData()
    }

    private func reloadData() {
        let config = SleepConfigurationManager.shared.configuration
        activeConfig = config
        let cycle = config.cycleRange(offset: cycleOffset)
        let service = SleepTrackingService.shared
        let cycleEvents = (try? service.fetchEvents(in: cycle)) ?? []
        events = cycleEvents.filter { $0.type != .bedtimeRoutineStart }
        incompleteEventReasons = (try? service.fetchIncompleteEventReasons()) ?? [:]
        metrics = try? service.calculateCycleMetrics(for: cycle, configuration: config)
        activeOngoingInterval = cycleOffset == 0
            ? (try? service.activeSleepInterval(in: cycle, configuration: config))
            : nil
    }

    private func colorForEvent(_ type: EventType) -> Color {
        switch type {
        case .sleep: return .indigo
        case .wake: return .orange
        case .bedtimeRoutineStart: return .purple
        case .sleepAttempt: return .teal
        }
    }

    private enum ExportFormat {
        case csv, json
    }

    @State private var shareItems: [Any] = []

    private func exportData(format: ExportFormat) {
        do {
            let all = try SleepTrackingService.shared.fetchAllEvents(ascending: true)
            let tempDir = FileManager.default.temporaryDirectory

            switch format {
            case .csv:
                let csvString = ExportService.shared.exportToCSV(events: all)
                let fileURL = tempDir.appendingPathComponent("baby_sleep_export.csv")
                try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
                shareItems = [fileURL]
                isSharePresented = true

            case .json:
                let jsonData = try ExportService.shared.exportToJSON(events: all)
                let fileURL = tempDir.appendingPathComponent("baby_sleep_export.json")
                try jsonData.write(to: fileURL)
                shareItems = [fileURL]
                isSharePresented = true
            }
        } catch {
            print("Export error: \(error)")
        }
    }
}

// ShareSheet helper
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
