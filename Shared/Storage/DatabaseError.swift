import Foundation

public enum DatabaseError: Error, LocalizedError, Sendable {
    case unableToOpen(String)
    case executionFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case transactionFailed(String)
    case recordNotFound
    case corruptedData(String)

    public var errorDescription: String? {
        switch self {
        case .unableToOpen(let message):
            return "No se pudo abrir la base de datos: \(message)"
        case .executionFailed(let message):
            return "Error al ejecutar sentencia SQL: \(message)"
        case .prepareFailed(let message):
            return "Error al preparar sentencia SQL: \(message)"
        case .stepFailed(let message):
            return "Error al procesar fila SQL: \(message)"
        case .transactionFailed(let message):
            return "Error en la transacción SQL: \(message)"
        case .recordNotFound:
            return "Registro no encontrado en la base de datos."
        case .corruptedData(let message):
            return "Datos corruptos o inválidos: \(message)"
        }
    }
}
