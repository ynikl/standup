import StandUpCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    StatusHero(snapshot: model.snapshot, threshold: model.settings.sedentaryThresholdMinutes)

                    HStack(spacing: 12) {
                        SummaryTile(title: "Today", value: "\(todaySummary.overdueCount)", caption: "overdue")
                        SummaryTile(title: "Overage", value: StandUpFormatting.minutes(todaySummary.totalOverageMinutes), caption: "total")
                        SummaryTile(title: "Longest", value: StandUpFormatting.minutes(todaySummary.longestContinuousSedentaryMinutes), caption: "sit")
                    }

                    IgnoreActionsView { duration in
                        model.ignore(duration)
                    }

                    PermissionBanner(permissionState: model.permissionState)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(Color.standCanvas)
            .navigationTitle("StandUp")
            .toolbar {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
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

private struct StatusHero: View {
    let snapshot: SedentarySnapshot
    let threshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(phaseTitle)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("Threshold \(threshold)m")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: phaseIcon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 52, height: 52)
                    .background(phaseColor.opacity(0.12), in: Circle())
            }

            Gauge(value: Double(min(snapshot.seatedMinutes ?? 0, threshold)), in: 0...Double(threshold)) {
                EmptyView()
            } currentValueLabel: {
                Text(StandUpFormatting.minutes(snapshot.seatedMinutes))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(phaseColor)
            .frame(maxWidth: .infinity)

            Text(phaseDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color.standSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var phaseTitle: String {
        switch snapshot.phase {
        case .monitoring:
            return "Monitoring"
        case .overdue:
            return "Stand now"
        case .ignored:
            return "Paused"
        case .paused(let reason):
            return reason == .sensorUnavailable ? "Sensor paused" : "Outside hours"
        }
    }

    private var phaseDetail: String {
        switch snapshot.phase {
        case .monitoring:
            return "Current sitting estimate is active."
        case .overdue:
            return "Stand or walk for 2 minutes to reset this session."
        case .ignored(let until):
            return "Reminders resume at \(StandUpFormatting.time(until))."
        case .paused:
            return "Sedentary time is not being accumulated right now."
        }
    }

    private var phaseIcon: String {
        switch snapshot.phase {
        case .monitoring:
            return "timer"
        case .overdue:
            return "exclamationmark.circle.fill"
        case .ignored:
            return "moon.zzz.fill"
        case .paused:
            return "pause.circle.fill"
        }
    }

    private var phaseColor: Color {
        switch snapshot.phase {
        case .monitoring:
            return .standAccent
        case .overdue:
            return .standAlert
        case .ignored:
            return .standInk
        case .paused:
            return .secondary
        }
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

private struct IgnoreActionsView: View {
    let ignore: (IgnoreDuration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skip reminders")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(IgnoreDuration.allCases, id: \.self) { duration in
                    Button {
                        ignore(duration)
                    } label: {
                        Label(duration.displayTitle, systemImage: icon(for: duration))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.standAccent)
                }
            }
        }
        .padding(16)
        .background(Color.standSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func icon(for duration: IgnoreDuration) -> String {
        switch duration {
        case .fifteenMinutes, .thirtyMinutes:
            return "timer"
        case .oneHour, .twoHours:
            return "clock"
        case .untilTomorrow:
            return "sunrise"
        }
    }
}

private struct PermissionBanner: View {
    let permissionState: PermissionState

    var body: some View {
        if permissionState.notificationsAllowed == false || permissionState.motionAllowed == false {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.standAlert)
                Text("Permissions need attention")
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .padding(14)
            .background(Color.standAlert.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
