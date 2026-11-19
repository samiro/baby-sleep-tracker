import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct SettingsView: View {
    @ObservedObject private var profileManager = BabyProfileManager.shared
    @AppStorage(BabyProfileManager.babyNameKey) private var storedBabyName: String = ""

    // Baby name state
    @State private var showEditBabyNameModal: Bool = false
    @State private var showResetBabyNameConfirmation: Bool = false

    // Configuration state
    @State private var nightStartDate: Date = Date()
    @State private var dayStartDate: Date = Date()

    // Active handle selection for direct tapping or stepping
    @State private var activeHandle: DragHandle = .dayStart

    // Feedback & alerts
    @State private var showReclassifyAlert = false
    @State private var reclassifyCount: Int = 0
    @State private var alertMessage: String = ""
    @State private var showAlert = false
    @State private var showResetConfirmation = false
    @State private var showClearDataConfirmation = false

    public enum DragHandle: String, CaseIterable, Identifiable {
        case dayStart = "dayStart"
        case nightStart = "nightStart"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .dayStart: return "☀️ Inicia el día / Fin de noche"
            case .nightStart: return "🌙 Inicia la noche / Fin de día"
            }
        }

        public var shortTitle: String {
            switch self {
            case .dayStart: return "☀️ Despertar"
            case .nightStart: return "🌙 Acostada"
            }
        }
    }

    public init() {}

    private var currentConfig: SleepScheduleConfiguration {
        let calendar = Calendar.current
        let nightH = calendar.component(.hour, from: nightStartDate)
        let nightM = calendar.component(.minute, from: nightStartDate)
        let dayH = calendar.component(.hour, from: dayStartDate)
        let dayM = calendar.component(.minute, from: dayStartDate)
        return SleepScheduleConfiguration(
            nightStartHour: nightH,
            nightStartMinute: nightM,
            dayStartHour: dayH,
            dayStartMinute: dayM
        )
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Section: Perfil / Nombre en homescreen
                Section {
                    HStack {
                        Text(profileManager.displayName)
                            .font(.system(size: 17, design: .rounded))
                            .foregroundColor(.primary)

                        Spacer()

                        Button {
                            showEditBabyNameModal = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.accentColor)
                                .frame(minWidth: 32, minHeight: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Editar")

                        Button {
                            showResetBabyNameConfirmation = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.red)
                                .frame(minWidth: 32, minHeight: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Eliminar")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Nombre en Homescreen", systemImage: "person.crop.circle")
                } footer: {
                    Text("Este nombre se mostrará en el encabezado y barra de navegación de la pantalla principal.")
                        .font(.caption)
                }

                // Section 1: Interactive 24-Hour Cycle Bar
                Section {
                    scheduleVisualCard
                } header: {
                    Label("Ciclo de 24 Horas Interactivo", systemImage: "clock.arrow.circlepath")
                } footer: {
                    Text("Arrastra el indicador de la barra para fijar la hora en que finaliza la noche e inicia el día (ej. 06:30), o la hora en que inicia la noche (ej. 19:30).")
                        .font(.caption)
                }

                // Section 2: Data Actions & Maintenance
                Section(header: Label("Mantenimiento de datos", systemImage: "wrench.and.screwdriver")) {
                    Button {
                        reclassifyPastEvents()
                    } label: {
                        Label("Aplicar a eventos pasados sin clasificar", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        showResetConfirmation = true
                    } label: {
                        Label("Restablecer ciclo 24h recomendado", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        showClearDataConfirmation = true
                    } label: {
                        Label("Reiniciar datos (Borrar todo y empezar de 0)", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                // Section 3: Pediatric Sleep Information
                Section(header: Label("Guía pediátrica", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("¿Por qué diferenciar siestas y noche?")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("En bebés, separar el descanso diurno (siestas) del descanso nocturno permite seguir con precisión la maduración del ritmo circadiano y controlar las ventanas de vigilia para evitar el sobrecansancio antes de dormir.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Section 4: Acerca de
                Section("Acerca de") {
                    HStack {
                        Text("Nombre de la aplicación")
                        Spacer()
                        Text(BabyProfileManager.defaultAppName)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Versión")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showEditBabyNameModal) {
                EditBabyNameSheet(profileManager: profileManager)
            }
            .onAppear {
                loadInitialConfig()
            }
            .confirmationDialog(
                "¿Restablecer nombre por defecto?",
                isPresented: $showResetBabyNameConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restablecer", role: .destructive) {
                    profileManager.setBabyName(nil)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se restablecerá el nombre por defecto (\(BabyProfileManager.defaultAppName)).")
            }
            .alert("Información", isPresented: $showAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog(
                "¿Restablecer ciclo 24h recomendado?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restablecer ciclo 24h recomendado (19:00 - 07:00)", role: .destructive) {
                    resetToDefaults()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se restaurará el horario recomendado de 24 horas (19:00 a 07:00).")
            }
            .confirmationDialog(
                "¿Eliminar todos los registros?",
                isPresented: $showClearDataConfirmation,
                titleVisibility: .visible
            ) {
                Button("Borrar todo y empezar de 0", role: .destructive) {
                    clearAllData()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción eliminará de forma irreversible todos los eventos y períodos de sueño registrados para comenzar desde cero.")
            }
        }
    }

    // MARK: - Subviews

    private var scheduleVisualCard: some View {
        let config = currentConfig
        let nightDurationText = SleepScheduleConfiguration.formatDurationText(config.nightWindowDuration)
        let dayDurationText = SleepScheduleConfiguration.formatDurationText(config.dayWindowDuration)

        let calendar = Calendar.current
        let dayMinutes = calendar.component(.hour, from: dayStartDate) * 60 + calendar.component(.minute, from: dayStartDate)
        let nightMinutes = calendar.component(.hour, from: nightStartDate) * 60 + calendar.component(.minute, from: nightStartDate)

        return VStack(spacing: 16) {
            // Summary Chips (Tappable to focus handle)
            HStack(spacing: 12) {
                // Day Window Box (Focus dayStart)
                Button {
                    activeHandle = .dayStart
                    triggerHaptic()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.orange)
                            Text("Día / Siestas")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            Spacer()
                            if activeHandle == .dayStart {
                                Image(systemName: "hand.point.down.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        Text("\(config.dayStartTimeString) – \(config.nightStartTimeString)")
                            .font(.headline)
                            .fontWeight(.heavy)
                            .foregroundColor(.primary)
                        Text("\(dayDurationText) de ventana")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(activeHandle == .dayStart ? 0.22 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(activeHandle == .dayStart ? Color.orange : Color.clear, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                // Night Window Box (Focus nightStart)
                Button {
                    activeHandle = .nightStart
                    triggerHaptic()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.indigo)
                            Text("Noche")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.indigo)
                            Spacer()
                            if activeHandle == .nightStart {
                                Image(systemName: "hand.point.down.fill")
                                    .font(.caption2)
                                    .foregroundColor(.indigo)
                            }
                        }
                        Text("\(config.nightStartTimeString) – \(config.dayStartTimeString)")
                            .font(.headline)
                            .fontWeight(.heavy)
                            .foregroundColor(.primary)
                        Text("\(nightDurationText) de ventana")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.indigo.opacity(activeHandle == .nightStart ? 0.22 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(activeHandle == .nightStart ? Color.indigo : Color.clear, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Interactive 24-Hour Timeline Bar with Draggable Handles
            Interactive24HourBar(
                dayMinutes: dayMinutes,
                nightMinutes: nightMinutes,
                activeHandle: $activeHandle,
                onDayMinutesChanged: { newMinutes in
                    updateDayTime(minutes: newMinutes)
                },
                onNightMinutesChanged: { newMinutes in
                    updateNightTime(minutes: newMinutes)
                }
            )
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Logic & Actions

    private func updateDayTime(minutes: Int) {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        dayStartDate = makeDate(hour: hour, minute: minute)
        saveConfig()
    }

    private func updateNightTime(minutes: Int) {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        nightStartDate = makeDate(hour: hour, minute: minute)
        saveConfig()
    }

    private func loadInitialConfig() {
        let config = SleepConfigurationManager.shared.configuration
        nightStartDate = makeDate(hour: config.nightStartHour, minute: config.nightStartMinute)
        dayStartDate = makeDate(hour: config.dayStartHour, minute: config.dayStartMinute)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func saveConfig() {
        let config = currentConfig
        SleepConfigurationManager.shared.save(config)
    }

    private func resetToDefaults() {
        SleepConfigurationManager.shared.resetToDefaults()
        loadInitialConfig()
    }

    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func reclassifyPastEvents() {
        do {
            let updated = try SleepTrackingService.shared.reclassifyUnspecifiedEvents()
            if updated > 0 {
                alertMessage = "Se han reclasificado exitosamente \(updated) evento(s) previo(s) según los horarios actuales."
            } else {
                alertMessage = "No se encontraron eventos sin clasificar pendientes de actualizar."
            }
            showAlert = true
        } catch {
            alertMessage = "Error al reclasificar eventos: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func clearAllData() {
        do {
            try SleepTrackingService.shared.resetAllData()
            alertMessage = "Todos los registros e intervalos han sido eliminados. Puedes comenzar a registrar desde cero."
            showAlert = true
        } catch {
            alertMessage = "Error al eliminar registros: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

// MARK: - Edit Baby Name Modal

public struct EditBabyNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileManager: BabyProfileManager
    @State private var name: String
    private let onSave: ((String?) -> Void)?

    public init(
        profileManager: BabyProfileManager = .shared,
        initialName: String? = nil,
        onSave: ((String?) -> Void)? = nil
    ) {
        self.profileManager = profileManager
        let startingName = initialName ?? profileManager.babyName ?? ""
        _name = State(initialValue: startingName)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre del bebé", text: $name)
                        .font(.system(size: 17, design: .rounded))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            save()
                        }
                } header: {
                    Text("Nombre del bebé")
                } footer: {
                    Text("Este nombre se mostrará en el encabezado y barra de navegación de la pantalla principal.")
                        .font(.caption)
                }
            }
            .navigationTitle("Editar nombre")
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
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? nil : trimmed
        if let onSave = onSave {
            onSave(finalName)
        } else {
            profileManager.setBabyName(finalName)
        }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        dismiss()
    }
}

// MARK: - Interactive 24-Hour Bar Component

private struct Interactive24HourBar: View {
    let dayMinutes: Int
    let nightMinutes: Int
    @Binding var activeHandle: SettingsView.DragHandle
    let onDayMinutesChanged: (Int) -> Void
    let onNightMinutesChanged: (Int) -> Void

    @State private var draggingHandle: SettingsView.DragHandle? = nil
    @State private var lastHapticMinute: Int = -1

    private let trackHeight: CGFloat = 26
    private let thumbSize: CGFloat = 32

    var body: some View {
        VStack(spacing: 8) {
            // Live active callout / readout
            HStack {
                if activeHandle == .dayStart {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.orange)
                        Text("☀️ Despertar:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(formatMinutes(dayMinutes))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text("· Inicia el día / Fin de noche")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundColor(.indigo)
                        Text("🌙 Acostada:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(formatMinutes(nightMinutes))
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text("· Inicia la noche / Fin de día")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // Timeline Track and Thumbs
            GeometryReader { geometry in
                let width = max(100, geometry.size.width)
                let dayX = CGFloat(dayMinutes) / 1440.0 * width
                let nightX = CGFloat(nightMinutes) / 1440.0 * width

                ZStack(alignment: .leading) {
                    // Colored Track Segments (00:00 to 24:00)
                    trackBackground(width: width, dayX: dayX, nightX: nightX)

                    // Day start thumb (☀️ Inicia el día)
                    thumbView(
                        icon: "sun.max.fill",
                        color: .orange,
                        timeText: formatMinutes(dayMinutes),
                        isSelected: activeHandle == .dayStart || draggingHandle == .dayStart
                    )
                    .position(x: dayX, y: trackHeight / 2)
                    .zIndex(activeHandle == .dayStart ? 2 : 1)

                    // Night start thumb (🌙 Inicia la noche)
                    thumbView(
                        icon: "moon.stars.fill",
                        color: .indigo,
                        timeText: formatMinutes(nightMinutes),
                        isSelected: activeHandle == .nightStart || draggingHandle == .nightStart
                    )
                    .position(x: nightX, y: trackHeight / 2)
                    .zIndex(activeHandle == .nightStart ? 2 : 1)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            handleDrag(at: gesture.location.x, width: width, dayX: dayX, nightX: nightX)
                        }
                        .onEnded { _ in
                            draggingHandle = nil
                        }
                )
            }
            .frame(height: trackHeight + 14)

            // Hour Tick Marks (00:00, 06:00, 12:00, 18:00, 24:00)
            HStack {
                Text("00:00")
                Spacer()
                Text("06:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("24:00")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func trackBackground(width: CGFloat, dayX: CGFloat, nightX: CGFloat) -> some View {
        HStack(spacing: 0) {
            if dayX < nightX {
                // 00:00 -> dayX is Night
                Rectangle()
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.85), Color.purple.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, dayX))

                // dayX -> nightX is Day
                Rectangle()
                    .fill(LinearGradient(colors: [Color.orange, Color.yellow], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, nightX - dayX))

                // nightX -> 24:00 is Night
                Rectangle()
                    .fill(LinearGradient(colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, width - nightX))
            } else {
                // Inverted schedule edge case
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: max(0, nightX))

                Rectangle()
                    .fill(Color.indigo)
                    .frame(width: max(0, dayX - nightX))

                Rectangle()
                    .fill(Color.orange)
                    .frame(width: max(0, width - dayX))
            }
        }
        .frame(height: trackHeight)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func thumbView(icon: String, color: Color, timeText: String, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: thumbSize, height: thumbSize)
                .shadow(color: Color.black.opacity(0.25), radius: isSelected ? 4 : 2, x: 0, y: isSelected ? 3 : 1)

            Circle()
                .stroke(color, lineWidth: isSelected ? 3 : 2)
                .frame(width: thumbSize, height: thumbSize)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
        }
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }

    private func handleDrag(at touchX: CGFloat, width: CGFloat, dayX: CGFloat, nightX: CGFloat) {
        if draggingHandle == nil {
            let distDay = abs(touchX - dayX)
            let distNight = abs(touchX - nightX)
            let chosen: SettingsView.DragHandle = distDay <= distNight ? .dayStart : .nightStart
            draggingHandle = chosen
            activeHandle = chosen
        }

        let clampedX = min(width, max(0, touchX))
        let totalMinutes = Int(round((clampedX / width) * 1440.0))
        // Snap to 15-minute intervals
        let snapped = min(1440, max(0, Int(round(Double(totalMinutes) / 15.0)) * 15))

        if snapped != lastHapticMinute {
            lastHapticMinute = snapped
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }

        if draggingHandle == .dayStart {
            onDayMinutesChanged(snapped)
        } else {
            onNightMinutesChanged(snapped)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        let min = minutes % 60
        return String(format: "%02d:%02d", hour, min)
    }
}
