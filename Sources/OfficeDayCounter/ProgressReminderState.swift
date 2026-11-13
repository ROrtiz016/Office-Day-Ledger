import Foundation

struct ProgressReminderState {
    let now: Date
    let markedDates: [Date]
    let calendar: Calendar

    var monthCount: Int {
        markedDates.filter { calendar.isDate($0, equalTo: now, toGranularity: .month) }.count
    }

    func matches(weekday: Int, hour: Int) -> Bool {
        calendar.component(.weekday, from: now) == weekday &&
            calendar.component(.hour, from: now) == hour
    }

    static func needsReminder(needed: Int, availableDays: Int, buffer: Int) -> Bool {
        needed > 0 && availableDays <= needed + buffer
    }

    static func paceMessage(needed: Int, availableDays: Int) -> String {
        guard needed <= availableDays else { return "Goal cannot be met with the remaining eligible weekdays" }
        let perWeek = max(1, Int(ceil(Double(needed) / Double(availableDays) * 5)))
        return "You need to go \(perWeek) time\(perWeek == 1 ? "" : "s") per week to meet your goal"
    }
}
