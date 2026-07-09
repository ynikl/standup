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
                            HistoryRow(record: record)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Restore") {
                                        model.restore(recordID: record.id)
                                    }
                                    .tint(.standAccent)

                                    Button("Movie") {
                                        model.correct(recordID: record.id, reason: .watchingMovie)
                                    }
                                    .tint(.standInk)

                                    Button("Meeting") {
                                        model.correct(recordID: record.id, reason: .meeting)
                                    }
                                    .tint(.standAlert)
                                }
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
