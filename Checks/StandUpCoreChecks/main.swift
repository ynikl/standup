import Foundation
import StandUpCore

struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(message: message)
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CheckFailure(message: message)
    }
    return value
}

let checks: [(String, () throws -> Void)] = [
    ("default settings match MVP decisions", checkDefaultSettings),
    ("threshold is clamped and rounded", checkThresholdNormalization),
    ("ignore choices are fixed", checkIgnoreChoices),
    ("until tomorrow resumes at next active window", checkUntilTomorrow),
    ("threshold notification fires at configured time", checkThresholdNotification),
    ("ignore window does not clear session", checkIgnoreWindow),
    ("pre-threshold ignore never reminds early", checkPreThresholdIgnorePlan),
    ("reminder plan stops at active-window end", checkReminderActiveWindowBoundary),
    ("reminder plan repeats and caps pending requests", checkReminderPlanCadence),
    ("dismissed notification repeats every ten minutes", checkRepeatReminder),
    ("continuous activity clears after two minutes", checkActivityClear),
    ("tick clears continuous active movement", checkTickActivityClear),
    ("sedentary movement interrupts active clear", checkInterruptedActivityClear),
    ("session state survives encoding and restoration", checkSessionRestoration),
    ("sensor unavailable pauses without backfilling", checkSensorUnavailable),
    ("outside active window does not notify", checkActiveWindow),
    ("daily summaries exclude corrected records", checkDailySummaries),
    ("trend windows include exact calendar days", checkTrendWindow)
]

var failures: [String] = []
for (name, check) in checks {
    do {
        try check()
        print("PASS \(name)")
    } catch {
        failures.append("\(name): \(error)")
        print("FAIL \(name): \(error)")
    }
}

if !failures.isEmpty {
    print("\n\(failures.count) check(s) failed")
    exit(1)
}

print("\nAll \(checks.count) checks passed")

func checkDefaultSettings() throws {
    let settings = StandUpSettings.default

    try expect(settings.sedentaryThresholdMinutes == 45, "default threshold should be 45 minutes")
    try expect(settings.activeClearMinutes == 2, "active clear should be 2 minutes")
    try expect(settings.repeatReminderMinutes == 10, "repeat reminder should be 10 minutes")
    try expect(settings.activeWindow.startMinuteOfDay == 9 * 60, "active window should start at 09:00")
    try expect(settings.activeWindow.endMinuteOfDay == 22 * 60, "active window should end at 22:00")
}

func checkThresholdNormalization() throws {
    try expect(StandUpSettings(sedentaryThresholdMinutes: 3).sedentaryThresholdMinutes == 15, "threshold lower bound")
    try expect(StandUpSettings(sedentaryThresholdMinutes: 121).sedentaryThresholdMinutes == 120, "threshold upper bound")
    try expect(StandUpSettings(sedentaryThresholdMinutes: 42).sedentaryThresholdMinutes == 40, "threshold rounds down to nearest five")
    try expect(StandUpSettings(sedentaryThresholdMinutes: 43).sedentaryThresholdMinutes == 45, "threshold rounds up to nearest five")
}

func checkIgnoreChoices() throws {
    try expect(IgnoreDuration.fifteenMinutes.minutes == 15, "15 minute ignore")
    try expect(IgnoreDuration.thirtyMinutes.minutes == 30, "30 minute ignore")
    try expect(IgnoreDuration.oneHour.minutes == 60, "1 hour ignore")
    try expect(IgnoreDuration.twoHours.minutes == 120, "2 hour ignore")
    try expect(IgnoreDuration.untilTomorrow.minutes == nil, "until tomorrow has no fixed minute length")
}

func checkUntilTomorrow() throws {
    let settings = StandUpSettings.default
    let start = Date.standUpCheck(hour: 20, minute: 15)
    let until = IgnoreDuration.untilTomorrow.endDate(startedAt: start, settings: settings, calendar: .standUpCheck)

    try expect(until == Date.standUpCheck(year: 2026, month: 7, day: 10, hour: 9, minute: 0), "until tomorrow should resume at next active-window start")
}

func checkThresholdNotification() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    try expect(engine.ingest(.activity(.sedentary), at: start).shouldNotify == false, "first sedentary sample should not notify")
    try expect(engine.snapshot(at: start.adding(minutes: 44)).phase == .monitoring, "44 minutes should still be monitoring")

    let output = engine.ingest(.tick, at: start.adding(minutes: 45))

    try expect(output.shouldNotify, "45 minutes should notify")
    try expect(output.notificationReason == .thresholdReached, "first notification reason")
    try expect(engine.snapshot(at: start.adding(minutes: 45)).phase == .overdue, "phase should be overdue")
    try expect(engine.snapshot(at: start.adding(minutes: 45)).seatedMinutes == 45, "seated minutes should be visible")
}

func checkIgnoreWindow() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    let ignored = engine.ingest(.ignore(.twoHours), at: start.adding(minutes: 46))

    try expect(ignored.shouldNotify == false, "ignore action should not notify")
    try expect(engine.snapshot(at: start.adding(minutes: 90)).phase == .ignored(until: start.adding(minutes: 166)), "2 hour ignore window")
    try expect(engine.snapshot(at: start.adding(minutes: 90)).seatedMinutes == 90, "ignore should not clear session")
    try expect(engine.ingest(.tick, at: start.adding(minutes: 120)).shouldNotify == false, "no notify during ignore")

    let afterIgnoreWindow = engine.ingest(.tick, at: start.adding(minutes: 167))

    try expect(afterIgnoreWindow.shouldNotify, "notify after ignore expires")
    try expect(afterIgnoreWindow.notificationReason == .repeatReminder, "after-ignore reason should be repeat")
}

func checkPreThresholdIgnorePlan() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.ignore(.fifteenMinutes), at: start.adding(minutes: 5))

    let plan = engine.reminderPlan(at: start.adding(minutes: 5))

    try expect(
        plan.reminders.first?.deliveryDate == start.adding(minutes: 45),
        "ignore ending before threshold must not remind early"
    )
    try expect(plan.reminders.first?.reason == .thresholdReached, "first planned reminder reason")
}

func checkReminderActiveWindowBoundary() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 21, minute: 30)

    _ = engine.ingest(.activity(.sedentary), at: start)

    let plan = engine.reminderPlan(at: start)

    try expect(plan.reminders.isEmpty, "22:15 threshold is outside active hours")
}

func checkReminderPlanCadence() throws {
    let settings = StandUpSettings(
        sedentaryThresholdMinutes: 15,
        activeWindow: ActiveWindow(startMinuteOfDay: 0, endMinuteOfDay: 24 * 60)
    )
    var engine = SedentaryEngine(settings: settings, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 0, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)

    let plan = engine.reminderPlan(at: start, limit: 60)

    try expect(plan.reminders.count == 60, "plan should respect pending-request cap")
    try expect(plan.reminders[0].deliveryDate == start.adding(minutes: 15), "threshold delivery")
    try expect(plan.reminders[0].reason == .thresholdReached, "first reminder reason")
    try expect(plan.reminders[1].deliveryDate == start.adding(minutes: 25), "repeat cadence")
    try expect(plan.reminders[1].reason == .repeatReminder, "repeat reminder reason")
}

func checkRepeatReminder() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    try expect(engine.ingest(.tick, at: start.adding(minutes: 45)).shouldNotify, "threshold notify")
    try expect(engine.ingest(.tick, at: start.adding(minutes: 54)).shouldNotify == false, "not enough time for repeat")

    let repeatOutput = engine.ingest(.tick, at: start.adding(minutes: 55))

    try expect(repeatOutput.shouldNotify, "repeat should fire")
    try expect(repeatOutput.notificationReason == .repeatReminder, "repeat reason")
}

func checkActivityClear() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    try expect(engine.ingest(.activity(.active), at: start.adding(minutes: 50)).endedRecords.isEmpty, "first active sample should not clear yet")

    let output = engine.ingest(.activity(.active), at: start.adding(minutes: 52))
    let record = try require(output.endedRecords.first, "record should end after two active minutes")

    try expect(record.sedentaryStartedAt == start, "record start")
    try expect(record.thresholdReachedAt == start.adding(minutes: 45), "threshold reached")
    try expect(record.endedAt == start.adding(minutes: 52), "record end")
    try expect(record.overageMinutes == 7, "overage minutes")
    try expect(record.endReason == .stoodUp, "end reason")
    try expect(engine.snapshot(at: start.adding(minutes: 52)).phase == .monitoring, "phase reset")
    try expect(engine.snapshot(at: start.adding(minutes: 52)).seatedMinutes == nil, "timer cleared")
}

func checkTickActivityClear() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    _ = engine.ingest(.activity(.active), at: start.adding(minutes: 50))

    let output = engine.ingest(.tick, at: start.adding(minutes: 52))

    try expect(output.endedRecords.first?.endReason == .stoodUp, "tick should finish active session")
}

func checkInterruptedActivityClear() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    _ = engine.ingest(.activity(.active), at: start.adding(minutes: 50))
    _ = engine.ingest(.activity(.sedentary), at: start.adding(minutes: 51))

    let output = engine.ingest(.tick, at: start.adding(minutes: 52))

    try expect(output.endedRecords.isEmpty, "sedentary signal should cancel active candidate")
}

func checkSessionRestoration() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    _ = engine.ingest(.tick, at: start.adding(minutes: 45))
    _ = engine.ingest(.ignore(.thirtyMinutes), at: start.adding(minutes: 46))

    let data = try JSONEncoder().encode(engine.sessionState)
    let state = try JSONDecoder().decode(SedentarySessionState.self, from: data)
    let restored = SedentaryEngine(settings: .default, calendar: .standUpCheck, sessionState: state)

    try expect(
        restored.snapshot(at: start.adding(minutes: 50)).phase == .ignored(until: start.adding(minutes: 76)),
        "restored ignore window"
    )
    try expect(restored.snapshot(at: start.adding(minutes: 50)).seatedMinutes == 50, "restored seated duration")
}

func checkSensorUnavailable() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let start = Date.standUpCheck(hour: 9, minute: 0)

    _ = engine.ingest(.activity(.sedentary), at: start)
    let unavailable = engine.ingest(.activity(.unavailable), at: start.adding(minutes: 30))

    try expect(unavailable.endedRecords == [], "no record before threshold")
    try expect(engine.snapshot(at: start.adding(minutes: 90)).phase == .paused(.sensorUnavailable), "sensor pause")
    try expect(engine.snapshot(at: start.adding(minutes: 90)).seatedMinutes == nil, "no backfilled seated time")
}

func checkActiveWindow() throws {
    var engine = SedentaryEngine(settings: .default, calendar: .standUpCheck)
    let evening = Date.standUpCheck(hour: 22, minute: 30)

    _ = engine.ingest(.activity(.sedentary), at: evening)
    let output = engine.ingest(.tick, at: evening.adding(minutes: 90))

    try expect(output.shouldNotify == false, "outside active window should not notify")
    try expect(engine.snapshot(at: evening.adding(minutes: 90)).phase == .paused(.outsideActiveWindow), "outside active window pause")
}

func checkDailySummaries() throws {
    let day = Date.standUpCheck(hour: 0, minute: 0)
    let records = [
        SedentaryRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sedentaryStartedAt: day.adding(hours: 9),
            thresholdReachedAt: day.adding(hours: 9, minutes: 45),
            endedAt: day.adding(hours: 10, minutes: 15),
            endReason: .stoodUp,
            ignoreEvents: []
        ),
        SedentaryRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sedentaryStartedAt: day.adding(hours: 13),
            thresholdReachedAt: day.adding(hours: 13, minutes: 45),
            endedAt: day.adding(hours: 14, minutes: 45),
            endReason: .stoodUp,
            ignoreEvents: [.init(duration: .thirtyMinutes, startedAt: day.adding(hours: 14), until: day.adding(hours: 14, minutes: 30))],
            correction: .excluded(reason: .watchingMovie)
        ),
        SedentaryRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            sedentaryStartedAt: day.adding(hours: 16),
            thresholdReachedAt: day.adding(hours: 16, minutes: 45),
            endedAt: day.adding(hours: 17, minutes: 55),
            endReason: .stoodUp,
            ignoreEvents: []
        )
    ]

    let summaries = SedentaryAnalytics.dailySummaries(
        records: records,
        endingOn: day.adding(hours: 23),
        days: 7,
        calendar: .standUpCheck
    )

    let today = try require(summaries.last, "today summary")
    try expect(today.overdueCount == 2, "corrected record excluded from count")
    try expect(today.totalOverageMinutes == 100, "total overage excludes corrected record")
    try expect(today.longestContinuousSedentaryMinutes == 115, "longest continuous sedentary")
}

func checkTrendWindow() throws {
    let end = Date.standUpCheck(year: 2026, month: 7, day: 9, hour: 23, minute: 0)

    try expect(SedentaryAnalytics.emptyDailySummaries(endingOn: end, days: 7, calendar: .standUpCheck).count == 7, "7 day window")
    try expect(SedentaryAnalytics.emptyDailySummaries(endingOn: end, days: 30, calendar: .standUpCheck).count == 30, "30 day window")
}

extension Calendar {
    static var standUpCheck: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

extension Date {
    static func standUpCheck(
        year: Int = 2026,
        month: Int = 7,
        day: Int = 9,
        hour: Int,
        minute: Int
    ) -> Date {
        DateComponents(
            calendar: .standUpCheck,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }

    func adding(hours: Int = 0, minutes: Int = 0) -> Date {
        addingTimeInterval(TimeInterval((hours * 60 + minutes) * 60))
    }
}
