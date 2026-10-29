import SwiftUI

public struct MainDashboardView: View {
    @State private var currentState: CurrentSleepState = .unknown
    @State private var mostRecentInterval: SleepInterval?
    @State private var todayMetrics: DayMetrics?
    @State private var feedbackMessage: String?
    @State private var showFeedbackAlert = false
    @State private var showAddEventSheet = false

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init() {}

    private var isSleeping: Bool {
        currentState.isSleeping
    }

    private var stateColor: Color {
        isSleeping ? .indigo : .orange
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header greeting & baby name
                    VStack(spacing: 4) {
                        Text("Emanuel")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(isSleeping ? "Durmiendo plácidamente" : "Despierto y activo")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 12)

                    // Notch / Dynamic Island Status Indicator
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text("Notch / Dynamic Island")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 5) {
                            Circle()
                                .fill(isSleeping ? Color.indigo : Color.secondary.opacity(0.6))
                                .frame(width: 6, height: 6)
                            Text(isSleeping ? "Activo en el Notch" : "Inactivo (solo durmiendo)")
                                .font(.system(size: 11, weight: isSleeping ? .bold : .medium))
                                .foregroundColor(isSleeping ? .indigo : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isSleeping ? Color.indigo.opacity(0.12) : Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        Task {
                            await LiveActivityManager.shared.syncWithCurrentState()
                        }
                    }

                    // Big Current State Card with Live Timer
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(stateColor.opacity(0.12))
                                .frame(width: 140, height: 140)

                            Circle()
                                .stroke(stateColor.opacity(0.3), lineWidth: 4)
                                .frame(width: 140, height: 140)

                            Image(systemName: isSleeping ? "moon.stars.fill" : "sun.max.fill")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundColor(stateColor)
                        }

                        VStack(spacing: 4) {
                            if let since = currentState.sinceDate {
                                Text(since, style: .timer)
                                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.primary)

                                Text(isSleeping ? "Tiempo durmiendo" : "Tiempo despierto")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("--:--")
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text("Sin registros aún")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    // Primary Action Buttons (Optimized for One-Handed Use)
                    VStack(spacing: 14) {
                        // "Se durmió" button
                        Button {
                            record(type: .sleep)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 20, weight: .bold))
                                Text("Se durmió")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .foregroundColor(isSleeping ? .secondary : .white)
                            .background(isSleeping ? Color.gray.opacity(0.2) : Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // "Despertó" button
                        Button {
                            record(type: .wake)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sun.max.fill")
                                    .font(.system(size: 20, weight: .bold))
                                Text("Despertó")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .foregroundColor(!isSleeping ? .secondary : .black)
                            .background(!isSleeping ? Color.gray.opacity(0.2) : Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // "Iniciar rutina" secondary action
                        Button {
                            record(type: .bedtimeRoutineStart)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Iniciar rutina de sueño")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.secondary)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    // Recent Interval & Quick Today Metrics
                    if let recent = mostRecentInterval {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Último intervalo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(recent.summaryText)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if let metrics = todayMetrics {
                        DailyMetricsCardView(metrics: metrics)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Emanuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TimelineHistoryView()
                    } label: {
                        Label("Historial", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .alert("Aviso", isPresented: $showFeedbackAlert) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(feedbackMessage ?? "")
            }
            .onAppear {
                refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sleepEventsDidChange)) { _ in
                refresh()
            }
            .onReceive(timer) { _ in
                // Keep view refreshed for live timers
            }
        }
    }

    private func record(type: EventType) {
        do {
            try SleepTrackingService.shared.recordEvent(type: type)
            refresh()
        } catch let error as SleepTrackingError {
            feedbackMessage = error.localizedDescription
            showFeedbackAlert = true
        } catch {
            feedbackMessage = "Error inesperado: \(error.localizedDescription)"
            showFeedbackAlert = true
        }
    }

    private func refresh() {
        let service = SleepTrackingService.shared
        currentState = (try? service.getCurrentState()) ?? .unknown
        mostRecentInterval = try? service.getMostRecentSleepInterval()
        todayMetrics = try? service.calculateDayMetrics(for: Date())
    }
}
