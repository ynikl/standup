import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: StandUpAppModel
    @State private var threshold: Double = 45
    @State private var startHour: Double = 9
    @State private var endHour: Double = 22

    var body: some View {
        NavigationStack {
            Form {
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
                threshold = Double(model.settings.sedentaryThresholdMinutes)
                startHour = Double(model.settings.activeWindow.startMinuteOfDay / 60)
                endHour = Double(model.settings.activeWindow.endMinuteOfDay / 60)
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
}
