import XCTest
@testable import OfficeDayCounter

final class BackupPayloadTests: XCTestCase {
    private func backup(date: String = "2026-11-02", pto: [String] = [], hour: Int = 9, version: Int? = 1) -> BackupPayload {
        BackupPayload(version: version, officeDays: [date], ptoDays: pto, excludedDays: [], officeSSID: "Office", monitoringEnabled: true, reminderWeekday: 2, reminderHour: hour, reminderFrequency: "weekly")
    }

    func testValidAndLegacyBackups() throws {
        try backup().validate()
        let data = try JSONEncoder().encode(backup(version: nil))
        try JSONDecoder().decode(BackupPayload.self, from: data).validate()
    }

    func testRejectsInvalidData() {
        XCTAssertThrowsError(try backup(date: "2026-02-30").validate())
        XCTAssertThrowsError(try backup(pto: ["2026-11-02"]).validate())
        XCTAssertThrowsError(try backup(hour: 24).validate())
        XCTAssertThrowsError(try backup(version: 2).validate())
    }

    func testBackupRoundTripPreservesRecordsAndSettings() throws {
        let original = BackupPayload(version: 1, officeDays: ["2026-01-02"], ptoDays: ["2026-01-05"], excludedDays: ["2026-01-06"], officeSSID: "Office", monitoringEnabled: true, reminderWeekday: 3, reminderHour: 14, reminderFrequency: "monthly")
        let restored = try JSONDecoder().decode(BackupPayload.self, from: JSONEncoder().encode(original))
        try restored.validate()
        XCTAssertEqual(restored.officeDays, original.officeDays)
        XCTAssertEqual(restored.ptoDays, original.ptoDays)
        XCTAssertEqual(restored.excludedDays, original.excludedDays)
        XCTAssertEqual(restored.officeSSID, original.officeSSID)
        XCTAssertEqual(restored.monitoringEnabled, original.monitoringEnabled)
        XCTAssertEqual(restored.reminderWeekday, original.reminderWeekday)
        XCTAssertEqual(restored.reminderHour, original.reminderHour)
        XCTAssertEqual(restored.reminderFrequency, original.reminderFrequency)
    }
}
