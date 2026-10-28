import Foundation
import AppIntents
import WidgetKit

public struct RecordSleepIntent: AppIntent {
    public static var title: LocalizedStringResource = "Se durmió"
    public static var description = IntentDescription("Registra que Emanuel se durmió.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SleepTrackingService.shared.recordEvent(type: .sleep)
            return .result(dialog: "Emanuel se durmió. Registrado.")
        } catch let error as SleepTrackingError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: "Error al registrar: \(error.localizedDescription)")
        }
    }
}

public struct RecordWakeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Despertó"
    public static var description = IntentDescription("Registra que Emanuel despertó.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SleepTrackingService.shared.recordEvent(type: .wake)
            return .result(dialog: "Emanuel despertó. Intervalo cerrado.")
        } catch let error as SleepTrackingError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: "Error al registrar: \(error.localizedDescription)")
        }
    }
}

public struct StartRoutineIntent: AppIntent {
    public static var title: LocalizedStringResource = "Iniciar rutina"
    public static var description = IntentDescription("Registra el inicio de la rutina previa a dormir.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SleepTrackingService.shared.recordEvent(type: .bedtimeRoutineStart)
            return .result(dialog: "Rutina iniciada.")
        } catch {
            return .result(dialog: "Error al registrar: \(error.localizedDescription)")
        }
    }
}
