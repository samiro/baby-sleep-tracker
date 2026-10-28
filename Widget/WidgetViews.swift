import SwiftUI
import WidgetKit
import AppIntents

public struct EmanuelSleepWidgetMediumView: View {
    let entry: SleepWidgetEntry
    @Environment(\.colorScheme) var colorScheme

    public init(entry: SleepWidgetEntry) {
        self.entry = entry
    }

    private var isSleeping: Bool {
        entry.state.isSleeping
    }

    private var stateColor: Color {
        isSleeping ? Color.indigo : Color.orange
    }

    private var stateTitle: String {
        switch entry.state {
        case .sleeping:
            return "Durmiendo"
        case .awake:
            return "Despierto"
        case .unknown:
            return "Sin registro"
        }
    }

    private var stateIcon: String {
        isSleeping ? "moon.stars.fill" : "sun.max.fill"
    }

    public var body: some View {
        HStack(spacing: 12) {
            // MARK: - Left Column: State & Elapsed Live Timer
            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack(spacing: 4) {
                    Text("Emanuel · Sueño")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                // Current State Badge
                HStack(spacing: 5) {
                    Image(systemName: stateIcon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(stateColor)
                    Text(stateTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(stateColor)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(stateColor.opacity(0.15))
                .clipShape(Capsule())

                // Elapsed Live Timer
                if let since = entry.state.sinceDate {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(since, style: .timer)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        Text(isSleeping ? "de sueño" : "despierto")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 1)
                } else {
                    Text("--:--")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                // Most Recent Sleep Interval
                VStack(alignment: .leading, spacing: 1) {
                    Text("Último intervalo")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    if let recent = entry.mostRecentInterval {
                        Text(recent.summaryText)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    } else {
                        Text("Ninguno registrado hoy")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.vertical, 4)

            // MARK: - Right Column: Large Action Buttons
            VStack(spacing: 6) {
                // Button 1: "Se durmió"
                Button(intent: RecordSleepIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Se durmió")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(isSleeping ? Color.secondary : Color.white)
                    .background(isSleeping ? Color.gray.opacity(0.2) : Color.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                // Button 2: "Despertó"
                Button(intent: RecordWakeIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Despertó")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(!isSleeping ? Color.secondary : Color.black)
                    .background(!isSleeping ? Color.gray.opacity(0.2) : Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                // Secondary Button: "Rutina"
                Button(intent: StartRoutineIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 10))
                        Text("Iniciar rutina")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .foregroundColor(.secondary)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 140)
        }
        .padding(.all, 8)
        .widgetURL(URL(string: "emanuelsleep://history"))
    }
}
