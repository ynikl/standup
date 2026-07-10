import StandUpCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        SummaryTile(title: "Today", value: "\(todaySummary.overdueCount)", caption: "overdue")
                        SummaryTile(title: "Overage", value: StandUpFormatting.minutes(todaySummary.totalOverageMinutes), caption: "total")
                        SummaryTile(title: "Longest", value: StandUpFormatting.minutes(todaySummary.longestContinuousSedentaryMinutes), caption: "sit")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(Color.standCanvas)
            .navigationTitle("StandUp")
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

private struct SummaryTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.standSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
