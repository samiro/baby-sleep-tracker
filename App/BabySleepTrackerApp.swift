import SwiftUI

@main
struct BabySleepTrackerApp: App {
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
