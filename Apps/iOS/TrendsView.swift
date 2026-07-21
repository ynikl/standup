import Charts
import StandUpCore
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var model: StandUpAppModel
    @State private var window = 7

    var body: some View {
        NavigationStack {
            Group {
                if model.records.isEmpty {
                    ContentUnavailableView {
                        Label("暂无趋势数据", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("积累几天久坐记录后，这里会显示你的变化趋势。")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            Picker("时间范围", selection: $window) {
                                Text("近 7 天").tag(7)
                                Text("近 30 天").tag(30)
                            }
                            .pickerStyle(.segmented)

                            TrendCard(title: "超时时长（分钟）") {
                                Chart(summaries) { summary in
                                    BarMark(
                                        x: .value("日期", summary.day, unit: .day),
                                        y: .value("分钟", summary.totalOverageMinutes)
                                    )
                                    .foregroundStyle(Color.standAlert.gradient)
                                }
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .day, count: window == 7 ? 1 : 5))
                                }
                            }

                            TrendCard(title: "超时次数") {
                                Chart(summaries) { summary in
                                    LineMark(
                                        x: .value("日期", summary.day, unit: .day),
                                        y: .value("次数", summary.overdueCount)
                                    )
                                    .foregroundStyle(Color.standAccent)
                                    PointMark(
                                        x: .value("日期", summary.day, unit: .day),
                                        y: .value("次数", summary.overdueCount)
                                    )
                                    .foregroundStyle(Color.standAccent)
                                }
                            }

                            TrendCard(title: "最长久坐（分钟）") {
                                Chart(summaries) { summary in
                                    AreaMark(
                                        x: .value("日期", summary.day, unit: .day),
                                        y: .value("分钟", summary.longestContinuousSedentaryMinutes)
                                    )
                                    .foregroundStyle(Color.standAccent.opacity(0.18))

                                    LineMark(
                                        x: .value("日期", summary.day, unit: .day),
                                        y: .value("分钟", summary.longestContinuousSedentaryMinutes)
                                    )
                                    .foregroundStyle(Color.standAccent)
                                }
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .background(Color.standCanvas.ignoresSafeArea())
            .navigationTitle("趋势")
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
                .foregroundStyle(Color.standInk)
            content
                .frame(height: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .standCard(padding: 16)
    }
}
