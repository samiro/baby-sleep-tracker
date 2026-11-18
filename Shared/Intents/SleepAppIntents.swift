import Foundation
import AppIntents
import WidgetKit

public struct RecordSleepIntent: AppIntent {
    public static var title: LocalizedStringResource = "Se durmió"
    public static var description = IntentDescription("Registra que el bebé se durmió.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SleepTrackingService.shared.recordEvent(type: .sleep)
            return .result(dialog: "\(BabyProfileManager.shared.displayName) se durmió. Registrado.")
        } catch let error as SleepTrackingError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: "Error al registrar: \(error.localizedDescription)")
        }
    }
}

public struct RecordWakeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Despertó"
    public static var description = IntentDescription("Registra que el bebé despertó.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SleepTrackingService.shared.recordEvent(type: .wake)
            return .result(dialog: "\(BabyProfileManager.shared.displayName) despertó. Intervalo cerrado.")
        } catch let error as SleepTrackingError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: "Error al registrar: \(error.localizedDescription)")
        }
    }
}
