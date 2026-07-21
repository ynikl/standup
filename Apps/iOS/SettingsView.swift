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
                    Section("应用状态") {
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
                                Text(model.isRetryingOperationalWork ? "重试中…" : "重新尝试")
                                Spacer()
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(model.isRetryingOperationalWork)
                    }
                }

                Section {
                    Stepper(value: $threshold, in: 15...120, step: 5) {
                        HStack {
                            Text("久坐提醒")
                            Spacer()
                            Text("\(Int(threshold)) 分钟")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("久坐提醒阈值")
                } footer: {
                    Text("连续久坐达到该时长后，手表会提醒你起身活动。")
                }

                Section {
                    Stepper(value: $startHour, in: 0...23, step: 1) {
                        HStack {
                            Text("开始")
                            Spacer()
                            Text(String(format: "%02d:00", Int(startHour)))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Stepper(value: $endHour, in: 1...24, step: 1) {
                        HStack {
                            Text("结束")
                            Spacer()
                            Text(String(format: "%02d:00", Int(endHour)))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("活动时段")
                } footer: {
                    Text("仅在该时段内监测久坐，其余时间自动暂停，不打扰休息。")
                }

                Section("隐私") {
                    Label("数据仅保存在本机", systemImage: "lock.shield")
                    Label("无需账号，不上传服务器", systemImage: "icloud.slash")
                }
            }
            .navigationTitle("设置")
            .scrollContentBackground(.hidden)
            .background(Color.standCanvas.ignoresSafeArea())
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
