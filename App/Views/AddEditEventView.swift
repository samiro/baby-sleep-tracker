import SwiftUI

public struct AddEditEventView: View {
    @Environment(\.dismiss) private var dismiss

    private let existingEvent: SleepEvent?
    private let onSave: (SleepEvent) -> Void
    private let onDelete: ((UUID) -> Void)?

    @State private var eventType: EventType
    @State private var timestamp: Date
    @State private var notes: String
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    public init(
        existingEvent: SleepEvent? = nil,
        initialDate: Date = Date(),
        onSave: @escaping (SleepEvent) -> Void,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        self.existingEvent = existingEvent
        self.onSave = onSave
        self.onDelete = onDelete

        let initialType: EventType
        if let type = existingEvent?.type, type == .wake {
            initialType = .wake
        } else {
            initialType = .sleep
        }
        _eventType = State(initialValue: initialType)
        _timestamp = State(initialValue: existingEvent?.timestamp ?? SleepEvent.clampedInitialTimestamp(initialDate))
        _notes = State(initialValue: existingEvent?.notes ?? "")
    }

    private var availableEventTypes: [EventType] {
        [.sleep, .wake]
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                }

                Section(header: Text("Tipo de evento")) {
                    Picker("Tipo", selection: $eventType) {
                        ForEach(availableEventTypes, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Fecha y Hora")) {
                    DatePicker(
                        "Hora del evento",
                        selection: $timestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .onChange(of: timestamp) { _, newValue in
                        if errorMessage != nil, (try? SleepEvent.validatedTimestamp(newValue)) != nil {
                            errorMessage = nil
                        }
                    }
                }

                Section(header: Text("Notas u observaciones")) {
                    TextField("Ej: Se durmió en brazos, con ruido blanco...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if existingEvent != nil, let onDelete = onDelete {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Eliminar evento", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingEvent == nil ? "Agregar evento" : "Editar evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        save()
                    }
                }
            }
            .confirmationDialog(
                "¿Eliminar este evento?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    if let existing = existingEvent, let onDelete = onDelete {
                        onDelete(existing.id)
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción eliminará el registro de forma permanente.")
            }
        }
    }

    private func save() {
        let configuration = SleepConfigurationManager.shared.configuration

        do {
            let event = try SleepEvent.makeValidatedFormEvent(
                existingEvent: existingEvent,
                type: eventType,
                timestamp: timestamp,
                notes: notes,
                configuration: configuration
            )
            errorMessage = nil
            onSave(event)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
