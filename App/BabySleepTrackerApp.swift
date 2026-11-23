import SwiftUI

@main
struct BabySleepTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: String = "dashboard"
    @State private var historyTargetDate: Date? = nil

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                MainDashboardView()
                    .tabItem {
                        Label("Hoy", systemImage: "moon.stars")
                    }
                    .tag("dashboard")

                TimelineHistoryView(targetDate: $historyTargetDate)
                    .tabItem {
                        Label("Historial", systemImage: "clock.arrow.circlepath")
                    }
                    .tag("history")

                MetricsAnalyticsView(onSelectHistoryDate: { date in
                    historyTargetDate = date
                    selectedTab = "history"
                })
                    .tabItem {
                        Label("Métricas", systemImage: "chart.bar.xaxis")
                    }
                    .tag("metrics")

                SettingsView()
                    .tabItem {
                        Label("Ajustes", systemImage: "gearshape.fill")
                    }
                    .tag("settings")
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .task {
                await LiveActivityManager.shared.syncWithCurrentState()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    Task {
                        await LiveActivityManager.shared.syncWithCurrentState()
                    }
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if url.scheme == "emanuelsleep" || url.scheme == "babysleeptracker" {
            if url.host == "today" || url.host == "dashboard" || url.host == nil || url.host?.isEmpty == true {
                selectedTab = "dashboard"
            } else if url.host == "history" {
                selectedTab = "history"
            } else if url.host == "metrics" || url.host == "analytics" {
                selectedTab = "metrics"
            } else if url.host == "settings" {
                selectedTab = "settings"
            }
        }
    }
}
