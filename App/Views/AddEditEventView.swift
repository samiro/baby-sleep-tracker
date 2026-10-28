import SwiftUI

public struct AddEditEventView: View {
    @Environment(\.dismiss) private var dismiss

    private let existingEvent: SleepEvent?
    private let onSave: (SleepEvent) -> Void
    private let onDelete: ((UUID) -> Void)?

    @State private var eventType: EventType
    @State private var timestamp: Date
    @State private var classification: SleepClassification
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

        _eventType = State(initialValue: existingEvent?.type ?? .sleep)
        _timestamp = State(initialValue: existingEvent?.timestamp ?? initialDate)
        _classification = State(initialValue: existingEvent?.classification ?? .unspecified)
        _notes = State(initialValue: existingEvent?.notes ?? "")
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
                        ForEach(EventType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Fecha y Hora")) {
                    DatePicker(
                        "Hora del evento",
                        selection: $timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }

                if eventType == .sleep {
                    Section(header: Text("Clasificación del sueño")) {
                        Picker("Clasificación", selection: $classification) {
                            ForEach(SleepClassification.allCases, id: \.self) { item in
                                Label(item.displayName, systemImage: item.iconName).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
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
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = trimmedNotes.isEmpty ? nil : trimmedNotes

        let event = SleepEvent(
            id: existingEvent?.id ?? UUID(),
            type: eventType,
            timestamp: timestamp,
            classification: eventType == .sleep ? classification : .unspecified,
            notes: finalNotes,
            createdAt: existingEvent?.createdAt ?? Date(),
            updatedAt: Date()
        )

        onSave(event)
        dismiss()
    }
}
