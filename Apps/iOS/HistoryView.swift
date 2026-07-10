import StandUpCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: StandUpAppModel

    var body: some View {
        NavigationStack {
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
            .background(Color.standCanvas)
            .navigationTitle("History")
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
                Spacer()
                Text("+\(record.overageMinutes)m")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(record.isExcludedFromStats ? .secondary : Color.standAlert)
                HistoryActionsMenu(record: record, correct: correct, restore: restore)
            }

            HStack(spacing: 10) {
                Label("\(record.continuousSedentaryMinutes)m sitting", systemImage: "chair")
                if !record.ignoreEvents.isEmpty {
                    Label("\(record.ignoreEvents.count) skip", systemImage: "moon.zzz")
                }
                if record.isExcludedFromStats {
                    Label("excluded", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
                    Label("Restore to trends", systemImage: "arrow.uturn.backward")
                }
            } else {
                Section("Exclude from trends") {
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
        .accessibilityLabel("Actions for \(StandUpFormatting.timeRange(record))")
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
