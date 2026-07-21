import StandUpCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TodayHeaderCard(summary: todaySummary)

                    HStack(spacing: 12) {
                        SummaryTile(
                            title: "提醒",
                            value: "\(todaySummary.overdueCount)",
                            caption: "次超时",
                            tint: .standAlert,
                            icon: "bell.badge"
                        )
                        SummaryTile(
                            title: "累计超时",
                            value: StandUpFormatting.compactMinutes(todaySummary.totalOverageMinutes),
                            caption: "今日",
                            tint: .standWarn,
                            icon: "hourglass"
                        )
                        SummaryTile(
                            title: "最长久坐",
                            value: StandUpFormatting.compactMinutes(todaySummary.longestContinuousSedentaryMinutes),
                            caption: "连续",
                            tint: .standAccent,
                            icon: "chair"
                        )
                    }

                    MonitoringHintCard()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(Color.standCanvas.ignoresSafeArea())
            .navigationTitle("久坐提醒")
        }
    }

    private var todaySummary: DailySedentarySummary {
        model.dailySummaries(days: 1).last ?? DailySedentarySummary(
            day: Date(),
            overdueCount: 0,
            totalOverageMinutes: 0,
            longestContinuousSedentaryMinutes: 0
        )
    }
}

private struct TodayHeaderCard: View {
    let summary: DailySedentarySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide)))
                .font(.caption)
                .foregroundStyle(Color.standInkSoft)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: summary.overdueCount == 0 ? "checkmark.seal.fill" : "figure.walk.motion")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(summary.overdueCount == 0 ? Color.standAccent : Color.standWarn)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.standInk)
                    Text(subline)
                        .font(.footnote)
                        .foregroundStyle(Color.standInkSoft)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .standCard(padding: 18)
    }

    private var headline: String {
        summary.overdueCount == 0 ? "今天状态不错 👏" : "今天久坐超时 \(summary.overdueCount) 次"
    }

    private var subline: String {
        summary.overdueCount == 0
            ? "还没有久坐超时记录，继续保持"
            : "记得多站起来走动一下"
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Color.standInk)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.standInk)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Color.standInkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .standCard(padding: 14)
    }
}

private struct MonitoringHintCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "applewatch.watchface")
                .font(.title3)
                .foregroundStyle(Color.standAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text("由 Apple Watch 实时监测")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.standInk)
                Text("久坐监测与提醒在手表上进行，iPhone 负责查看历史与趋势。数据仅保存在本机。")
                    .font(.caption)
                    .foregroundStyle(Color.standInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .standCard(padding: 16)
    }
}
