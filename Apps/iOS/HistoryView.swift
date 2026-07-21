import StandUpCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.records.isEmpty {
                    ContentUnavailableView {
                        Label("还没有久坐记录", systemImage: "clock.badge.checkmark")
                    } description: {
                        Text("戴上 Apple Watch 保持监测，久坐超时的记录会出现在这里。")
                    }
                } else {
                    List {
                        ForEach(groupedRecords.keys.sorted(by: >), id: \.self) { day in
                            Section(day.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(groupedRecords[day] ?? []) { record in
                                    HistoryRow(
                                        record: record,
                                        correct: { reason in
                                            model.correct(recordID: record.id, reason: reason)
                                        },
                                        restore: {
                                            model.restore(recordID: record.id)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.standCanvas.ignoresSafeArea())
            .navigationTitle("历史")
        }
    }

    private var groupedRecords: [Date: [SedentaryRecord]] {
        Dictionary(grouping: model.records) { record in
            Calendar.current.startOfDay(for: record.thresholdReachedAt)
        }
    }
}

private struct HistoryRow: View {
    let record: SedentaryRecord
    let correct: (CorrectionReason) -> Void
    let restore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(StandUpFormatting.timeRange(record))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.standInk)
                Spacer()
                Text("+\(record.overageMinutes) 分钟")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(record.isExcludedFromStats ? Color.standInkSoft : Color.standAlert)
                HistoryActionsMenu(record: record, correct: correct, restore: restore)
            }

            HStack(spacing: 12) {
                Label("久坐 \(record.continuousSedentaryMinutes) 分钟", systemImage: "chair")
                if !record.ignoreEvents.isEmpty {
                    Label("延后 \(record.ignoreEvents.count) 次", systemImage: "moon.zzz")
                }
                if record.isExcludedFromStats {
                    Label("已排除", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(Color.standInkSoft)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.standSurface)
    }
}

private struct HistoryActionsMenu: View {
    let record: SedentaryRecord
    let correct: (CorrectionReason) -> Void
    let restore: () -> Void

    var body: some View {
        Menu {
            if record.isExcludedFromStats {
                Button(action: restore) {
                    Label("恢复到趋势统计", systemImage: "arrow.uturn.backward")
                }
            } else {
                Section("从趋势中排除") {
                    ForEach(CorrectionReason.allCases, id: \.rawValue) { reason in
                        Button {
                            correct(reason)
                        } label: {
                            Label(reason.displayTitle, systemImage: icon(for: reason))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("\(StandUpFormatting.timeRange(record)) 的操作")
    }

    private func icon(for reason: CorrectionReason) -> String {
        switch reason {
        case .watchingMovie:
            return "film"
        case .meeting:
            return "person.2"
        case .alreadyStood:
            return "figure.stand"
        case .other:
            return "questionmark.circle"
        }
    }
}
