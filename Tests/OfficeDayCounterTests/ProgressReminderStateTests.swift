import XCTest
@testable import OfficeDayCounter

final class ProgressReminderStateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testReminderMatchesSelectedWeekdayAndActualHour() {
        let state = ProgressReminderState(now: date(2026, 11, 16, 9), markedDates: [], calendar: calendar)
        XCTAssertTrue(state.matches(weekday: 2, hour: 9))
        XCTAssertFalse(state.matches(weekday: 2, hour: 0))
        XCTAssertFalse(state.matches(weekday: 3, hour: 9))
    }

    func testCountUsesCurrentMonthAcrossYears() {
        let state = ProgressReminderState(
            now: date(2026, 11, 16, 9),
            markedDates: [date(2026, 11, 2), date(2026, 11, 3), date(2026, 10, 30), date(2025, 11, 3)],
            calendar: calendar
        )
        XCTAssertEqual(state.monthCount, 2)
    }

    func testPaceIdentifiesUnreachableGoal() {
        XCTAssertEqual(ProgressReminderState.paceMessage(needed: 4, availableDays: 3), "Goal cannot be met with the remaining eligible weekdays")
        XCTAssertEqual(ProgressReminderState.paceMessage(needed: 3, availableDays: 3), "You need to go 5 times per week to meet your goal")
    }

    func testReminderIncludesZeroRemainingDays() {
        XCTAssertTrue(ProgressReminderState.needsReminder(needed: 1, availableDays: 0, buffer: 2))
        XCTAssertFalse(ProgressReminderState.needsReminder(needed: 1, availableDays: 4, buffer: 2))
        XCTAssertFalse(ProgressReminderState.needsReminder(needed: 0, availableDays: 0, buffer: 2))
    }
}
