import SwiftUI

public struct TimelineHistoryView: View {
    @State private var selectedDate: Date = Date()
    @State private var events: [SleepEvent] = []
    @State private var metrics: DayMetrics?
    @State private var editingEvent: SleepEvent?
    @State private var isAddingEvent = false
    @State private var eventToDelete: SleepEvent?
    @State private var showDeleteConfirmation = false
    @State private var showExportSheet = false
    @State private var csvExportString: String = ""
    @State private var jsonExportData: Data = Data()
    @State private var isSharePresented = false

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Date Navigation Bar
                    dateNavigationBar

                    // Day Metrics Summary
                    if let metrics = metrics {
                        DailyMetricsCardView(metrics: metrics)
                    }

                    // Sleep Intervals Section
                    intervalsSection

                    // Raw Events Timeline Section
                    rawEventsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
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
                    initialDate: selectedDate,
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
            .sheet(isPresented: $isSharePresented) {
                ShareSheet(items: shareItems)
            }
            .onAppear {
                reloadData()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sleepEventsDidChange)) { _ in
                reloadData()
            }
        }
    }

    // MARK: - Components

    private var dateNavigationBar: some View {
        HStack {
            Button {
                changeDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(isToday(selectedDate) ? "Hoy" : (isYesterday(selectedDate) ? "Ayer" : dateFormatter.string(from: selectedDate)))
                    .font(.headline)
                if isToday(selectedDate) || isYesterday(selectedDate) {
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                changeDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }

    private var intervalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intervalos de sueño")
                .font(.headline)

            if let intervals = metrics?.sleepIntervals, !intervals.isEmpty {
                ForEach(intervals) { interval in
                    HStack(spacing: 12) {
                        Image(systemName: interval.classification == .nap ? "sun.haze.fill" : "moon.stars.fill")
                            .font(.system(size: 20))
                            .foregroundColor(interval.classification == .nap ? .orange : .indigo)
                            .frame(width: 36, height: 36)
                            .background((interval.classification == .nap ? Color.orange : Color.indigo).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
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
                            Text(interval.summaryText)
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
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                Text("No hay intervalos registrados en este día.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var rawEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Registro de eventos")
                .font(.headline)

            if events.isEmpty {
                Text("Sin eventos en este día.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(events) { event in
                        HStack(spacing: 12) {
                            Image(systemName: event.type.iconName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(colorForEvent(event.type))
                                .frame(width: 32, height: 32)
                                .background(colorForEvent(event.type).opacity(0.15))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(event.type.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    if event.type == .sleep {
                                        Text("(\(event.classification.displayName))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
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

                            Menu {
                                Button {
                                    editingEvent = event
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    eventToDelete = event
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func changeDay(by offset: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = newDate
            reloadData()
        }
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isYesterday(_ date: Date) -> Bool {
        Calendar.current.isDateInYesterday(date)
    }

    private func reloadData() {
        let service = SleepTrackingService.shared
        events = (try? service.fetchEvents(for: selectedDate)) ?? []
        metrics = try? service.calculateDayMetrics(for: selectedDate)
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
                let fileURL = tempDir.appendingPathComponent("emanuel_sleep_export.csv")
                try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
                shareItems = [fileURL]
                isSharePresented = true

            case .json:
                let jsonData = try ExportService.shared.exportToJSON(events: all)
                let fileURL = tempDir.appendingPathComponent("emanuel_sleep_export.json")
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
