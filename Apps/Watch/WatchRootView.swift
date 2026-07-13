import StandUpCore
import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        TabView {
            WatchStatusView()
            WatchIgnoreView()
            WatchSettingsView()
        }
        .tabViewStyle(.verticalPage)
        .tint(.watchAccent)
    }
}

private struct WatchStatusView: View {
    @EnvironmentObject private var model: StandUpAppModel
    @State private var timelineStart = Date()

    var body: some View {
        TimelineView(.periodic(from: timelineStart, by: 60)) { context in
            VStack(spacing: 10) {
                HStack {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(color)
                    Spacer()
                    WatchOperationalRetryButton()
                }
                .frame(height: 44)

                Text(StandUpFormatting.minutes(model.snapshot.seatedMinutes))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Gauge(value: Double(min(model.snapshot.seatedMinutes ?? 0, model.settings.sedentaryThresholdMinutes)), in: 0...Double(model.settings.sedentaryThresholdMinutes)) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                .tint(color)

                Text("Goal \(model.settings.sedentaryThresholdMinutes)m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .containerBackground(.watchSurface, for: .navigation)
            .onAppear {
                model.refresh()
            }
            .task(id: context.date) {
                model.refresh(now: context.date)
            }
        }
    }

    private var title: String {
        switch model.snapshot.phase {
        case .monitoring:
            return "Tracking"
        case .overdue:
            return "Stand now"
        case .ignored:
            return "Skipped"
        case .paused(let reason):
            return reason == .sensorUnavailable ? "Sensor paused" : "Off hours"
        }
    }

    private var icon: String {
        switch model.snapshot.phase {
        case .monitoring:
            return "timer"
        case .overdue:
            return "figure.stand"
        case .ignored:
            return "moon.zzz.fill"
        case .paused:
            return "pause.fill"
        }
    }

    private var color: Color {
        switch model.snapshot.phase {
        case .monitoring:
            return .watchAccent
        case .overdue:
            return .watchAlert
        case .ignored:
            return .watchInk
        case .paused:
            return .secondary
        }
    }
}

private struct WatchOperationalRetryButton: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        Group {
            if let error = model.operationalError {
                Button {
                    Task {
                        await model.retryOperationalWork()
                    }
                } label: {
                    Group {
                        if model.isRetryingOperationalWork {
                            ProgressView()
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.watchAlert)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isRetryingOperationalWork)
                .accessibilityLabel("Retry failed operation")
                .accessibilityHint(error)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44)
    }
}

private struct WatchIgnoreView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        List {
            ForEach(IgnoreDuration.allCases, id: \.self) { duration in
                Button {
                    model.ignore(duration)
                } label: {
                    Label(duration.displayTitle, systemImage: icon(for: duration))
                }
            }
        }
        .navigationTitle("Skip")
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

private struct WatchSettingsView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Threshold")
                .font(.headline)

            Text("\(model.settings.sedentaryThresholdMinutes)m")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            Slider(value: thresholdBinding, in: 15...120, step: 5)
                .tint(.watchAccent)
        }
        .padding(.horizontal, 12)
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(model.settings.sedentaryThresholdMinutes) },
            set: { model.updateThreshold(minutes: Int($0)) }
        )
    }
}

private extension ShapeStyle where Self == Color {
    static var watchSurface: Color { Color(red: 0.075, green: 0.083, blue: 0.079) }
}

private extension Color {
    static let watchAccent = Color(red: 0.267, green: 0.82, blue: 0.737)
    static let watchAlert = Color(red: 1.0, green: 0.42, blue: 0.32)
    static let watchInk = Color(red: 0.85, green: 0.88, blue: 0.84)
}
