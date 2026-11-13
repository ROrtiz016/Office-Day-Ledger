import Foundation

struct BackupPayload: Codable {
    let version: Int?
    let officeDays: [String]
    let ptoDays: [String]
    let excludedDays: [String]
    let officeSSID: String
    let monitoringEnabled: Bool
    let reminderWeekday: Int
    let reminderHour: Int
    let reminderFrequency: String

    func validate() throws {
        guard version == nil || version == 1 else { throw BackupError.invalid("Unsupported backup version.") }
        guard (2...6).contains(reminderWeekday), (0...23).contains(reminderHour),
              ["weekly", "monthly"].contains(reminderFrequency) else {
            throw BackupError.invalid("The reminder settings are invalid.")
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard (officeDays + ptoDays + excludedDays).allSatisfy({ key in
            guard let date = formatter.date(from: key) else { return false }
            return formatter.string(from: date) == key
        }) else { throw BackupError.invalid("The backup contains an invalid date.") }
        guard Set(officeDays).isDisjoint(with: Set(ptoDays)) else {
            throw BackupError.invalid("A date cannot be both an office day and PTO.")
        }
    }
}

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
