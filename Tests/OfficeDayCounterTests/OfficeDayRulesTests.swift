import XCTest
@testable import OfficeDayCounter

final class OfficeDayRulesTests: XCTestCase {
    func testWeekendsAndExcludedDatesAreNotAvailable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6))!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        XCTAssertTrue(OfficeDayRules.isAvailable(friday, dayKey: "2026-03-06", excludedDays: [], calendar: calendar))
        XCTAssertFalse(OfficeDayRules.isAvailable(sunday, dayKey: "2026-03-08", excludedDays: [], calendar: calendar))
        XCTAssertFalse(OfficeDayRules.isAvailable(monday, dayKey: "2026-03-09", excludedDays: ["2026-03-09"], calendar: calendar))
        XCTAssertTrue(OfficeDayRules.isAvailable(monday, dayKey: "2026-03-09", excludedDays: [], calendar: calendar))
    }
}
