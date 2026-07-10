import StandUpCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: StandUpAppModel
    @State private var threshold: Double = 45
    @State private var startHour: Double = 9
    @State private var endHour: Double = 22

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.operationalError {
                    Section("App status") {
                        Label {
                            Text(error)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.standAlert)
                        }

                        Button {
                            Task {
                                await model.retryOperationalWork()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isRetryingOperationalWork {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(model.isRetryingOperationalWork ? "Retrying..." : "Try again")
                                Spacer()
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(model.isRetryingOperationalWork)
                    }
                }

                Section("Sedentary threshold") {
                    Stepper(value: $threshold, in: 15...120, step: 5) {
                        HStack {
                            Text("Remind after")
                            Spacer()
                            Text("\(Int(threshold)) min")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Active hours") {
                    Stepper(value: $startHour, in: 0...23, step: 1) {
                        HStack {
                            Text("Start")
                            Spacer()
                            Text("\(Int(startHour)):00")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Stepper(value: $endHour, in: 1...24, step: 1) {
                        HStack {
                            Text("End")
                            Spacer()
                            Text(endHour == 24 ? "24:00" : "\(Int(endHour)):00")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Privacy") {
                    Label("Local data only", systemImage: "lock.shield")
                    Label("No account or server sync", systemImage: "icloud.slash")
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Color.standCanvas)
            .onAppear {
                syncControls(with: model.settings)
            }
            .onChange(of: model.settings) { _, settings in
                syncControls(with: settings)
            }
            .onChange(of: threshold) { _, newValue in
                model.updateThreshold(minutes: Int(newValue))
            }
            .onChange(of: startHour) { _, newValue in
                model.updateActiveWindow(startHour: Int(newValue), endHour: Int(endHour))
            }
            .onChange(of: endHour) { _, newValue in
                model.updateActiveWindow(startHour: Int(startHour), endHour: Int(newValue))
            }
        }
    }

    private func syncControls(with settings: StandUpSettings) {
        threshold = Double(settings.sedentaryThresholdMinutes)
        startHour = Double(settings.activeWindow.startMinuteOfDay / 60)
        endHour = Double(settings.activeWindow.endMinuteOfDay / 60)
    }
}
