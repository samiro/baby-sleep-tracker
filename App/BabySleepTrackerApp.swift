import SwiftUI

@main
struct BabySleepTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: String = "dashboard"

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                MainDashboardView()
                    .tabItem {
                        Label("Hoy", systemImage: "moon.stars")
                    }
                    .tag("dashboard")

                TimelineHistoryView()
                    .tabItem {
                        Label("Historial", systemImage: "clock.arrow.circlepath")
                    }
                    .tag("history")
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
        if url.scheme == "emanuelsleep" {
            if url.host == "history" {
                selectedTab = "history"
            }
        }
    }
}
