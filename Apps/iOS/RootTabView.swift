import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("今日", systemImage: "figure.stand")
                }

            HistoryView()
                .tabItem {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                }

            TrendsView()
                .tabItem {
                    Label("趋势", systemImage: "chart.bar.xaxis")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
        }
        .tint(.standAccent)
    }
}
