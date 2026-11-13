import CoreWLAN
@preconcurrency import CoreLocation
import Foundation
import SwiftUI
@preconcurrency import UserNotifications
import ServiceManagement

@MainActor
final class OfficeDayStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = OfficeDayStore()

    @Published private(set) var officeDays: Set<String>
    @Published private(set) var ptoDays: Set<String>
    @Published private(set) var currentSSID: String?
    @Published private(set) var pendingDayKey: String?
    @Published private(set) var locationAccessGranted = false
    @Published private(set) var notificationProblem: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published private(set) var loginProblem: String?
    @Published private(set) var excludedDays: Set<String>
    @Published var officeSSIDInput: String
    @Published var excludedDaysInput: String
    @Published var monitoringEnabled: Bool
    @Published var reminderWeekday: Int
    @Published var reminderHour: Int
    @Published var reminderFrequency: String
    @Published private(set) var displayedMonth: Date

    private let defaults = UserDefaults.standard
    private var monitorTimer: Timer?
    private var progressTimer: Timer?
    private let locationManager = CLLocationManager()
    private var lastPromptedDayKey: String?
    private var activePromptToken: String?
    private var progressNotificationsInFlight = Set<String>()
    private var observedMonth = Calendar.current.startOfMonth(for: Date())
    private let goal = 12
    private let progressReminderBuffer = 2
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private override init() {
        officeDays = Set(defaults.stringArray(forKey: "officeDays") ?? [])
        ptoDays = Set(defaults.stringArray(forKey: "ptoDays") ?? [])
        officeSSIDInput = defaults.string(forKey: "officeSSID") ?? ""
        let storedExcludedDays = Set(defaults.stringArray(forKey: "excludedDays") ?? [])
        excludedDays = storedExcludedDays
        excludedDaysInput = storedExcludedDays.sorted().joined(separator: ", ")
        monitoringEnabled = defaults.bool(forKey: "monitoringEnabled")
        reminderWeekday = defaults.object(forKey: "reminderWeekday") as? Int ?? 2
        reminderHour = defaults.object(forKey: "reminderHour") as? Int ?? 9
        reminderFrequency = defaults.string(forKey: "reminderFrequency") ?? "weekly"
        displayedMonth = Calendar.current.startOfMonth(for: Date())
        lastPromptedDayKey = defaults.string(forKey: "lastPromptedDayKey")
        locationAccessGranted = Self.hasLocationAccess(locationManager.authorizationStatus)
        super.init()
        if loginStatus == .requiresApproval { loginProblem = "Allow Office Day Counter in System Settings > General > Login Items." }
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar(identifier: .gregorian)
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "dd-MM-yyyy"
        excludedDaysInput = storedExcludedDays.sorted().compactMap { key in
            guard let date = dayFormatter.date(from: key) else { return nil }
            return inputFormatter.string(from: date)
        }.joined(separator: ", ")
        locationManager.delegate = self
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dayChanged), name: .NSCalendarDayChanged, object: nil)
        if monitoringEnabled { locationManager.requestWhenInUseAuthorization() }
        startMonitoring()
        startProgressMonitoring()
        requestNotificationAccessAndCheck()
    }

    var todayIsMarked: Bool { isMarked(Date()) }
    var currentMonthCount: Int { (officeDays.union(ptoDays)).filter(isInDisplayedMonth).count }
    var remainingDays: Int { max(0, goal - currentMonthCount) }
    var monthlyGoal: Int { goal }
    var monthTitle: String { monthFormatter.string(from: displayedMonth) }

    @objc private func systemWoke() {
        loginStatus = SMAppService.mainApp.status
        updateMonthAfterRollover()
        checkNetwork()
        checkMonthlyProgress()
        objectWillChange.send()
    }

    @objc private func dayChanged() {
        updateMonthAfterRollover()
        checkNetwork()
        checkMonthlyProgress()
        objectWillChange.send()
    }

    private func updateMonthAfterRollover() {
        let currentMonth = Calendar.current.startOfMonth(for: Date())
        if displayedMonth == observedMonth && currentMonth != observedMonth {
            displayedMonth = Calendar.current.startOfMonth(for: Date())
        }
        observedMonth = currentMonth
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginProblem = nil
        } catch {
            loginProblem = "Could not change launch at login: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
        if loginStatus == .requiresApproval { loginProblem = "Allow Office Day Counter in System Settings > General > Login Items." }
    }

    var paceMessage: String {
        guard currentMonthCount < goal else { return "Goal met for this month" }
        let needed = goal - currentMonthCount
        let weekdaysLeft = weekdaysRemaining(from: Calendar.current.startOfDay(for: Date()), in: displayedMonth)
        guard weekdaysLeft > 0 else { return "No weekdays left this month" }
        return ProgressReminderState.paceMessage(needed: needed, availableDays: weekdaysLeft)
    }

    struct MonthlySummary: Identifiable {
        let month: Date
        let count: Int
        var id: String { month.formatted(.dateTime.year().month()) }
    }

    var monthlyHistory: [MonthlySummary] {
        let calendar = Calendar.current
        return (0..<6).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: displayedMonth) else { return nil }
            return MonthlySummary(month: month, count: markedDays(in: month).count)
        }
    }

    /// Returns the persisted office days in calendar order for a report.
    func markedDays(in month: Date) -> [Date] {
        (officeDays.union(ptoDays)).compactMap(dayFormatter.date(from:))
            .filter { isAvailableOfficeDay($0) && Calendar.current.isDate($0, equalTo: month, toGranularity: .month) }
            .sorted()
    }

    func isPTO(_ date: Date) -> Bool {
        ptoDays.contains(dayKey(for: date))
    }

    func exportCurrentMonthReport() {
        let reportDates = markedDays(in: displayedMonth)
        let reportMonth = DateFormatter()
        reportMonth.dateFormat = "yyyy-MM"
        let dateColumn = DateFormatter()
        dateColumn.dateFormat = "yyyy-MM-dd"

        var csv = "date,type\n"
        csv += reportDates.map {
            let type = isPTO($0) ? "PTO" : "office"
            return "\(dateColumn.string(from: $0)),\(type)"
        }.joined(separator: "\n")
        csv += "\n\nmonth,days_marked,monthly_goal\n"
        csv += "\(reportMonth.string(from: displayedMonth)),\(reportDates.count),\(goal)\n"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "office-days-\(reportMonth.string(from: displayedMonth)).csv"
        panel.title = "Save monthly report"
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showBackupMessage("Could not save report: \(error.localizedDescription)")
        }
    }

    func exportCurrentMonthPDF() {
        let reportDates = markedDays(in: displayedMonth)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let monthKey = String(dayKey(for: displayedMonth).prefix(7))
        let lines = reportDates.map {
            "\(formatter.string(from: $0)) — \(isPTO($0) ? "PTO" : "Office day")"
        }
        let view = MonthlyReportPDFView(month: monthKey, count: reportDates.count, goal: goal, dates: lines)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "office-days-\(monthKey).pdf"
        panel.title = "Save monthly report"
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = view.dataWithPDF(inside: view.bounds)
        do {
            try data.write(to: url)
        } catch {
            showBackupMessage("Could not save PDF: \(error.localizedDescription)")
        }
    }

    func exportBackup() {
        let backup = BackupPayload(
            version: 1,
            officeDays: officeDays.sorted(),
            ptoDays: ptoDays.sorted(),
            excludedDays: excludedDays.sorted(),
            officeSSID: officeSSIDInput,
            monitoringEnabled: monitoringEnabled,
            reminderWeekday: reminderWeekday,
            reminderHour: reminderHour,
            reminderFrequency: reminderFrequency
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backup) else { showBackupMessage("Could not create backup."); return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "office-day-backup.json"
        panel.title = "Export backup"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) } catch { showBackupMessage("Could not save backup: \(error.localizedDescription)") }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import backup"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let backup: BackupPayload
        do {
            backup = try JSONDecoder().decode(BackupPayload.self, from: Data(contentsOf: url))
            try backup.validate()
        } catch {
            showBackupMessage("Could not import backup: \(error.localizedDescription)")
            return
        }

        let confirmation = NSAlert()
        confirmation.messageText = "Replace existing data?"
        confirmation.informativeText = "This backup contains \(backup.officeDays.count) office days, \(backup.ptoDays.count) PTO days, and \(backup.excludedDays.count) excluded dates. Importing replaces all current records and settings. Export a backup first if you want to keep them."
        confirmation.addButton(withTitle: "Replace Data")
        confirmation.addButton(withTitle: "Cancel")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        officeDays = Set(backup.officeDays)
        ptoDays = Set(backup.ptoDays)
        excludedDays = Set(backup.excludedDays)
        officeSSIDInput = backup.officeSSID
        monitoringEnabled = backup.monitoringEnabled
        reminderWeekday = backup.reminderWeekday
        reminderHour = backup.reminderHour
        reminderFrequency = backup.reminderFrequency
        persistAllSettings()
        excludedDaysInput = formattedExcludedDays()
        monitorTimer?.invalidate()
        monitorTimer = nil
        invalidateWiFiPrompt()
        currentSSID = nil
        lastPromptedDayKey = nil
        defaults.removeObject(forKey: "lastPromptedDayKey")
        defaults.removeObject(forKey: "lastProgressReminderKey")
        if monitoringEnabled {
            locationManager.requestWhenInUseAuthorization()
            requestNotificationAccessAndCheck()
            startMonitoring()
        }
        checkMonthlyProgress()
        showBackupMessage("Backup imported successfully.")
    }

    private func showBackupMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    private func persistAllSettings() {
        defaults.set(officeDays.sorted(), forKey: "officeDays")
        defaults.set(ptoDays.sorted(), forKey: "ptoDays")
        defaults.set(excludedDays.sorted(), forKey: "excludedDays")
        defaults.set(officeSSIDInput, forKey: "officeSSID")
        defaults.set(monitoringEnabled, forKey: "monitoringEnabled")
        defaults.set(reminderWeekday, forKey: "reminderWeekday")
        defaults.set(reminderHour, forKey: "reminderHour")
        defaults.set(reminderFrequency, forKey: "reminderFrequency")
    }

    private func formattedExcludedDays() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return excludedDays.sorted().compactMap { key in
            guard let date = dayFormatter.date(from: key) else { return nil }
            return formatter.string(from: date)
        }.joined(separator: ", ")
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    var calendarCells: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let leading = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        let total = Int(ceil(Double(leading + range.count) / 7.0)) * 7
        return (0..<total).map { index in
            let day = index - leading + 1
            guard day > 0, day <= range.count else { return nil }
            return calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        }
    }

    var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    func moveMonth(by amount: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth),
              next <= Calendar.current.startOfMonth(for: Date()) else { return }
        displayedMonth = next
    }

    func isMarked(_ date: Date) -> Bool {
        let key = dayKey(for: date)
        return isAvailableOfficeDay(date) && (officeDays.contains(key) || ptoDays.contains(key))
    }

    func canEdit(_ date: Date) -> Bool {
        isAvailableOfficeDay(date) && Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date())
    }

    func toggleDay(_ date: Date) {
        guard canEdit(date) else { return }
        let key = dayKey(for: date)
        if ptoDays.contains(key) {
            ptoDays.remove(key)
        } else if officeDays.contains(key) {
            officeDays.remove(key)
            ptoDays.insert(key)
        } else {
            officeDays.insert(key)
        }
        persistDays()
        checkMonthlyProgress()
    }

    @discardableResult
    func saveOfficeSSID() -> Bool {
        officeSSIDInput = officeSSIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !officeSSIDInput.isEmpty else {
            defaults.removeObject(forKey: "officeSSID")
            return false
        }
        defaults.set(officeSSIDInput, forKey: "officeSSID")
        checkNetwork()
        return true
    }

    func saveExcludedDays() -> Bool {
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar(identifier: .gregorian)
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "dd-MM-yyyy"
        let values = excludedDaysInput
            .split { $0 == "," || $0 == "\n" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let validValues = values.compactMap { value -> String? in
            guard let date = inputFormatter.date(from: value) else { return nil }
            return dayFormatter.string(from: date)
        }
        guard validValues.count == values.count else { return false }
        excludedDays = Set(validValues)
        excludedDaysInput = excludedDays.sorted().compactMap { key in
            guard let date = dayFormatter.date(from: key) else { return nil }
            return inputFormatter.string(from: date)
        }.joined(separator: ", ")
        defaults.set(excludedDays.sorted(), forKey: "excludedDays")
        return true
    }

    func saveReminderSettings() {
        defaults.set(reminderWeekday, forKey: "reminderWeekday")
        defaults.set(reminderHour, forKey: "reminderHour")
        defaults.set(reminderFrequency, forKey: "reminderFrequency")
        defaults.removeObject(forKey: "lastProgressReminderKey")
        checkMonthlyProgress()
    }

    func toggleMonitoring() {
        monitoringEnabled.toggle()
        defaults.set(monitoringEnabled, forKey: "monitoringEnabled")
        if monitoringEnabled {
            locationManager.requestWhenInUseAuthorization()
            requestNotificationAccessAndCheck()
            startMonitoring()
        } else {
            monitorTimer?.invalidate()
            monitorTimer = nil
            invalidateWiFiPrompt()
        }
    }

    private func invalidateWiFiPrompt() {
        if let token = activePromptToken {
            let identifier = "office-day-\(token)"
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        activePromptToken = nil
        pendingDayKey = nil
    }

    func handleWiFiNotification(dayKey: String, token: String, count: Bool) {
        guard monitoringEnabled, token == activePromptToken, pendingDayKey == dayKey else { return }
        if count { markDay(withKey: dayKey) }
        clearPendingDay(dayKey)
    }

    func markDay(withKey key: String) {
        guard key == dayKey(for: Date()), let date = dayFormatter.date(from: key),
              canEdit(date), !ptoDays.contains(key), !officeDays.contains(key) else { return }
        officeDays.insert(key)
        persistDays()
        checkMonthlyProgress()
    }

    func clearPendingDay(_ key: String) {
        if key == dayKey(for: Date()) {
            lastPromptedDayKey = key
            defaults.set(key, forKey: "lastPromptedDayKey")
        }
        if pendingDayKey == key { invalidateWiFiPrompt() }
    }

    func confirmPendingDay() {
        guard let pendingDayKey else { return }
        markDay(withKey: pendingDayKey)
        clearPendingDay(pendingDayKey)
    }

    func dismissPendingDay() {
        if let pendingDayKey { clearPendingDay(pendingDayKey) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAccessGranted = Self.hasLocationAccess(manager.authorizationStatus)
        if locationAccessGranted { checkNetwork() }
    }

    private func startMonitoring() {
        guard monitoringEnabled, monitorTimer == nil else { return }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNetwork() }
        }
        checkNetwork()
    }

    private func startProgressMonitoring() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkMonthlyProgress() }
        }
        checkMonthlyProgress()
    }

    func requestNotificationAccessAndCheck() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                Task { @MainActor in
                    self?.notificationProblem = settings.authorizationStatus == .denied || settings.alertSetting == .disabled
                        ? "Enable notifications and alerts in System Settings to receive Wi-Fi prompts." : nil
                }
            }
            Task { @MainActor in
                self?.checkNetwork()
                self?.checkMonthlyProgress()
            }
        }
    }

    private func checkNetwork() {
        let todayKey = dayKey(for: Date())
        if let pendingDayKey, pendingDayKey != todayKey { invalidateWiFiPrompt() }
        guard monitoringEnabled, !officeSSIDInput.isEmpty else { return }
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        currentSSID = ssid
        guard ssid == officeSSIDInput else { return }

        let today = Date()
        guard isAvailableOfficeDay(today) else { return }
        guard !officeDays.contains(todayKey), !ptoDays.contains(todayKey), pendingDayKey != todayKey, lastPromptedDayKey != todayKey else { return }
        pendingDayKey = todayKey
        let token = UUID().uuidString
        activePromptToken = token

        let content = UNMutableNotificationContent()
        content.title = "Office Wi-Fi detected"
        content.body = "Count today as an office day?"
        content.sound = .default
        content.categoryIdentifier = "OFFICE_DAY_CONFIRMATION"
        content.userInfo = ["dayKey": todayKey, "token": token]
        let request = UNNotificationRequest(identifier: "office-day-\(token)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                self?.notificationProblem = "Could not send the Wi-Fi notification. Open the app to confirm and check notification settings."
            }
        }
    }

    private func checkMonthlyProgress() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let markedDates = (officeDays.union(ptoDays)).compactMap(dayFormatter.date(from:))
            .filter(isAvailableOfficeDay)
        let progress = ProgressReminderState(now: now, markedDates: markedDates, calendar: calendar)

        let monthKey = monthKey(for: now)
        if progress.monthCount >= goal {
            notifyGoalReached(for: monthKey)
            return
        }

        guard progress.matches(weekday: reminderWeekday, hour: reminderHour) else { return }

        let needed = goal - progress.monthCount
        let remainingWeekdays = weekdaysRemaining(from: today, in: now)
        guard ProgressReminderState.needsReminder(needed: needed, availableDays: remainingWeekdays, buffer: progressReminderBuffer) else { return }

        let reminderKey = reminderFrequency == "monthly" ? monthKey : weekKey(for: today)
        guard defaults.string(forKey: "lastProgressReminderKey") != reminderKey else { return }

        let content = UNMutableNotificationContent()
        content.title = "Office day goal reminder"
        content.body = "You need \(needed) more office day\(needed == 1 ? "" : "s") and have \(remainingWeekdays) weekday\(remainingWeekdays == 1 ? "" : "s") left this month."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "office-day-progress-\(monthKey)",
            content: content,
            trigger: nil
        )
        sendProgressNotification(request, defaultsKey: "lastProgressReminderKey", value: reminderKey)
    }

    private func notifyGoalReached(for monthKey: String) {
        guard defaults.string(forKey: "lastGoalReachedMonth") != monthKey else { return }

        let content = UNMutableNotificationContent()
        content.title = "Office day goal complete!"
        content.body = "Congratulations! You completed your goal of \(goal) office days this month."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "office-day-goal-\(monthKey)",
            content: content,
            trigger: nil
        )
        sendProgressNotification(request, defaultsKey: "lastGoalReachedMonth", value: monthKey)
    }

    private func sendProgressNotification(_ request: UNNotificationRequest, defaultsKey: String, value: String) {
        let flightKey = "\(defaultsKey):\(value)"
        guard progressNotificationsInFlight.insert(flightKey).inserted else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
            guard allowed else {
                Task { @MainActor in self?.progressNotificationsInFlight.remove(flightKey) }
                return
            }
            center.add(request) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.progressNotificationsInFlight.remove(flightKey)
                    if error == nil { self.defaults.set(value, forKey: defaultsKey) }
                }
            }
        }
    }

    private func weekdaysRemaining(from start: Date, in month: Date) -> Int {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let lastDay = calendar.date(byAdding: .day, value: range.count - 1, to: firstDay) else {
            return 0
        }

        var date = max(start, firstDay)
        var count = 0
        while date <= lastDay {
            if isAvailableOfficeDay(date) && !isMarked(date) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return count
    }

    private func persistDays() {
        defaults.set(officeDays.sorted(), forKey: "officeDays")
        defaults.set(ptoDays.sorted(), forKey: "ptoDays")
    }

    private func dayKey(for date: Date) -> String { dayFormatter.string(from: date) }

    private func monthKey(for date: Date) -> String {
        String(dayKey(for: date).prefix(7))
    }

    private func weekKey(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    private func isAvailableOfficeDay(_ date: Date) -> Bool {
        OfficeDayRules.isAvailable(date, dayKey: dayKey(for: date), excludedDays: excludedDays, calendar: Calendar.current)
    }

    private func isInDisplayedMonth(_ key: String) -> Bool {
        guard let date = dayFormatter.date(from: key) else { return false }
        return isAvailableOfficeDay(date) && Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)
    }

    private static func hasLocationAccess(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

private final class MonthlyReportPDFView: NSView {
    private let month: String
    private let count: Int
    private let goal: Int
    private let dates: [String]

    init(month: String, count: Int, goal: Int, dates: [String]) {
        self.month = month
        self.count = count
        self.goal = goal
        self.dates = dates
        super.init(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: "Office Day Report").draw(at: NSPoint(x: 48, y: 720), withAttributes: titleAttributes)
        NSString(string: "Month: \(month)").draw(at: NSPoint(x: 48, y: 680), withAttributes: bodyAttributes)
        NSString(string: "Days marked: \(count) / \(goal)").draw(at: NSPoint(x: 48, y: 655), withAttributes: bodyAttributes)
        NSString(string: "Office days").draw(at: NSPoint(x: 48, y: 610), withAttributes: titleAttributes)

        for (index, date) in dates.enumerated() {
            let y = 580 - CGFloat(index * 22)
            guard y > 48 else { break }
            NSString(string: "• \(date)").draw(at: NSPoint(x: 60, y: y), withAttributes: bodyAttributes)
        }
    }
}
