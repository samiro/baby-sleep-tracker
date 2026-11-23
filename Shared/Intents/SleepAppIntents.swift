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
            return .result(dialog: "\(BabyProfileManager.shared.currentDisplayName()) se durmió. Registrado.")
        } catch let error as SleepTrackingError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: "Error al registrar: \(error.localizedDescription)")
        }
    }
}

public struct RecordWakeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Se despertó"
    public static var description = IntentDescription("Registra que el bebé se despertó.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try SleepTrackingService.shared.recordEvent(type: .wake)
            return .result(dialog: "\(BabyProfileManager.shared.currentDisplayName()) se despertó. Intervalo cerrado.")
        } catch let error as SleepTrackingError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: "Error al registrar: \(error.localizedDescription)")
        }
    }
}

#if os(iOS)
/// Background-executable Live Activity intent for recording sleep directly from the Lock Screen
/// without requiring device unlock.
public struct LiveActivityRecordSleepIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Se durmió"
    public static var description = IntentDescription("Registra que el bebé se durmió desde la pantalla de bloqueo.")
    public static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static var isDiscoverable: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        _ = try? SleepTrackingService.shared.recordEvent(type: .sleep)
        await LiveActivityManager.shared.syncWithCurrentState()
        return .result()
    }
}

/// Background-executable Live Activity intent for recording wake directly from the Lock Screen
/// without requiring device unlock.
public struct LiveActivityRecordWakeIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Se despertó"
    public static var description = IntentDescription("Registra que el bebé se despertó desde la pantalla de bloqueo.")
    public static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static var isDiscoverable: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        _ = try? SleepTrackingService.shared.recordEvent(type: .wake)
        await LiveActivityManager.shared.syncWithCurrentState()
        return .result()
    }
}
#endif
