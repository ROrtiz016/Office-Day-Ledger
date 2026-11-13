import Foundation

enum OfficeDayRules {
    static func isAvailable(_ date: Date, dayKey: String, excludedDays: Set<String>, calendar: Calendar) -> Bool {
        (2...6).contains(calendar.component(.weekday, from: date)) && !excludedDays.contains(dayKey)
    }
}
