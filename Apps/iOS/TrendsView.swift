import Charts
import StandUpCore
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var model: StandUpAppModel
    @State private var window = 7

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Window", selection: $window) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)

                    TrendCard(title: "Overdue minutes") {
                        Chart(summaries) { summary in
                            BarMark(
                                x: .value("Day", summary.day, unit: .day),
                                y: .value("Minutes", summary.totalOverageMinutes)
                            )
                            .foregroundStyle(Color.standAlert.gradient)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: window == 7 ? 1 : 5))
                        }
                    }

                    TrendCard(title: "Overdue count") {
                        Chart(summaries) { summary in
                            LineMark(
                                x: .value("Day", summary.day, unit: .day),
                                y: .value("Count", summary.overdueCount)
                            )
                            .foregroundStyle(Color.standAccent)
                            PointMark(
                                x: .value("Day", summary.day, unit: .day),
                                y: .value("Count", summary.overdueCount)
                            )
                            .foregroundStyle(Color.standAccent)
                        }
                    }

                    TrendCard(title: "Longest sitting stretch") {
                        Chart(summaries) { summary in
                            AreaMark(
                                x: .value("Day", summary.day, unit: .day),
                                y: .value("Minutes", summary.longestContinuousSedentaryMinutes)
                            )
                            .foregroundStyle(Color.standInk.opacity(0.22))

                            LineMark(
                                x: .value("Day", summary.day, unit: .day),
                                y: .value("Minutes", summary.longestContinuousSedentaryMinutes)
                            )
                            .foregroundStyle(Color.standInk)
                        }
                    }
                }
                .padding(18)
            }
            .background(Color.standCanvas)
            .navigationTitle("Trends")
        }
    }

    private var summaries: [DailySedentarySummary] {
        model.dailySummaries(days: window)
    }
}

private struct TrendCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
                .frame(height: 220)
        }
        .padding(16)
        .background(Color.standSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
