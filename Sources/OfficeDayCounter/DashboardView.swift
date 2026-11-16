import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct DashboardView: View {
    @ObservedObject var store: OfficeDayStore
    @Environment(\.openWindow) private var openWindow
    @State private var settingsExpanded = false
    @State private var saveMessage: String?
    @State private var exclusionMessage: String?
    @State private var historyExpanded = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            header
            progress
            reportButton
            history
            calendar
            dayLegend
            networkStatus
            if store.monitoringEnabled && !store.locationAccessGranted {
                Button("Open Location Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                }.controlSize(.small)
            }
            if let problem = store.notificationProblem, store.monitoringEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem).font(.system(size: 10)).foregroundStyle(.orange)
                    Button("Open Notification Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }.controlSize(.small)
                    Button("Refresh notification status") { store.requestNotificationAccessAndCheck() }
                        .controlSize(.small)
                }
            }
            settings
            openWindowButton
            quitButton
        }
        .padding(18)
        }
        // MenuBarExtra sizes its panel from this view's ideal size. A ScrollView
        // with only a maximum height can otherwise collapse to an empty strip.
        .frame(width: 360, height: min(700, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Office Wi-Fi detected", isPresented: Binding(
            get: { store.pendingDayKey != nil },
            set: { if !$0 { store.dismissPendingDay() } }
        )) {
            Button("Count today") { store.confirmPendingDay() }
            Button("Not today", role: .cancel) { store.dismissPendingDay() }
        } message: {
            Text("Count today as an office day?")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("OFFICE DAY LEDGER")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text(store.monthTitle)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
            }
            Spacer()
            Button { store.moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help("Previous month")
            Button { store.moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(Calendar.current.isDate(store.displayedMonth, equalTo: Date(), toGranularity: .month))
            .help("Next month")
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(store.currentMonthCount)")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("/ \(store.monthlyGoal) days")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.remainingDays == 0 ? "GOAL MET" : "\(store.remainingDays) TO GO")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(store.remainingDays == 0 ? Color.green : Color.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor))
                    Capsule()
                        .fill(Color(red: 0.16, green: 0.49, blue: 0.39))
                        .frame(width: geometry.size.width * min(Double(store.currentMonthCount) / Double(store.monthlyGoal), 1))
                }
            }
            .frame(height: 7)
            Text(store.paceMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Office days and PTO count toward the 12-day goal. Weekends and excluded dates do not count.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var reportButton: some View {
        HStack {
            Button {
                store.exportCurrentMonthReport()
            } label: {
                Label("Download report", systemImage: "arrow.down.doc")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                store.exportCurrentMonthPDF()
            } label: {
                Label("Download PDF", systemImage: "doc.richtext")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
            Text(store.monthTitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { historyExpanded.toggle() } label: {
                HStack {
                    Label("Monthly history", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)

            if historyExpanded {
                VStack(spacing: 5) {
                    ForEach(store.monthlyHistory) { summary in
                        HStack {
                            Text(summary.month.formatted(.dateTime.month(.wide).year()))
                            Spacer()
                            Text("\(summary.count) / \(store.monthlyGoal)")
                                .foregroundStyle(summary.count >= store.monthlyGoal ? .green : .secondary)
                        }
                        .font(.system(size: 11))
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    private var calendar: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(store.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 18)
            }
            ForEach(Array(store.calendarCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let marked = store.isMarked(date)
        let isPTO = store.isPTO(date)
        let isToday = Calendar.current.isDateInToday(date)
        return Button { store.toggleDay(date) } label: {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 12, weight: marked ? .semibold : .regular, design: .rounded))
                .foregroundStyle(marked ? Color.white : (store.canEdit(date) ? Color.primary : Color.secondary.opacity(0.4)))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    if marked {
                        RoundedRectangle(cornerRadius: 7).fill(isPTO ? Color.purple : Color(red: 0.16, green: 0.49, blue: 0.39))
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.82, green: 0.38, blue: 0.23), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!store.canEdit(date))
        .help(isPTO ? "Remove PTO day" : (marked ? "Mark as PTO" : "Mark as office day"))
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(marked ? (isPTO ? "PTO" : "Office day") : "Not marked")
        .accessibilityHint("Activate to cycle between office day, PTO, and unmarked.")
    }

    private var networkStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(!store.monitoringEnabled ? Color.gray : (!store.locationAccessGranted || store.officeSSIDInput.isEmpty || store.currentSSID == nil || store.notificationProblem != nil ? Color.orange : Color.green))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(!store.monitoringEnabled ? "Wi-Fi detection off" : (!store.locationAccessGranted || store.officeSSIDInput.isEmpty || store.currentSSID == nil || store.notificationProblem != nil ? "Wi-Fi detection needs attention" : "Wi-Fi detection on"))
                    .font(.system(size: 12, weight: .medium))
                 Text(!store.monitoringEnabled ? "Turn on detection in settings" : (!store.locationAccessGranted
                     ? "Location access needed to read Wi-Fi" : (store.officeSSIDInput.isEmpty ? "Save an office Wi-Fi name" : (store.currentSSID.map { "Connected to \($0)" } ?? "Wi-Fi name unavailable"))))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if store.pendingDayKey != nil {
                Label("Confirm in notification", systemImage: "bell.badge.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(red: 0.72, green: 0.34, blue: 0.19))
            }
        }
        .padding(.top, 2)
    }

    private var dayLegend: some View {
        HStack(spacing: 14) {
            legendItem(color: Color(red: 0.16, green: 0.49, blue: 0.39), title: "Office day")
            legendItem(color: .purple, title: "PTO")
            Spacer()
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .help("Select a date to cycle through office day, PTO, and unmarked.")
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { settingsExpanded.toggle() } label: {
                HStack {
                    Label("Network automation", systemImage: "wifi")
                    Spacer()
                    Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)

            if settingsExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Select a calendar date to cycle through office day, PTO, and unmarked.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        TextField("Office Wi-Fi name", text: $store.officeSSIDInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Button("Save") {
                            saveMessage = store.saveOfficeSSID()
                                ? "Saved"
                                : "Enter a Wi-Fi name"
                        }
                            .controlSize(.small)
                    }
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(saveMessage == "Saved" ? Color.green : Color.orange)
                    }
                    Text("Holidays and vacation dates (dd-MM-yyyy, comma separated)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Excluded dates do not count, even if previously marked. Remove an exclusion to restore its mark.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        TextField("25-12-2026, 26-12-2026", text: $store.excludedDaysInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                        Button("Save") {
                            exclusionMessage = store.saveExcludedDays()
                                ? "Saved"
                                : "Use dd-MM-yyyy dates"
                        }
                            .controlSize(.small)
                    }
                    if let exclusionMessage {
                        Text(exclusionMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(exclusionMessage == "Saved" ? Color.green : Color.orange)
                    }
                    HStack {
                        Text("Ask before counting a detected day")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Toggle("Wi-Fi detection", isOn: Binding(
                            get: { store.monitoringEnabled },
                            set: { _ in store.toggleMonitoring() }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    Divider()
                    Toggle("Launch at login", isOn: Binding(
                        get: { store.loginStatus == .enabled || store.loginStatus == .requiresApproval },
                        set: { store.setLaunchAtLogin($0) }
                    ))
                    .font(.system(size: 11))
                    if let problem = store.loginProblem {
                        Text(problem).font(.system(size: 10)).foregroundStyle(.orange)
                    }
                    Text("Progress reminders")
                        .font(.system(size: 11, weight: .semibold))
                    HStack {
                        Picker("Day", selection: Binding(
                            get: { store.reminderWeekday },
                            set: { store.reminderWeekday = $0; store.saveReminderSettings() }
                        )) {
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(3)
                            Text("Wednesday").tag(4)
                            Text("Thursday").tag(5)
                            Text("Friday").tag(6)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Picker("Frequency", selection: Binding(
                            get: { store.reminderFrequency },
                            set: { store.reminderFrequency = $0; store.saveReminderSettings() }
                        )) {
                            Text("Weekly").tag("weekly")
                            Text("Monthly").tag("monthly")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Picker("Time", selection: Binding(
                        get: { store.reminderHour },
                        set: { store.reminderHour = $0; store.saveReminderSettings() }
                    )) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Backup and restore")
                        .font(.system(size: 11, weight: .semibold))
                    HStack {
                        Button("Export backup") { store.exportBackup() }
                            .controlSize(.small)
                        Button("Import backup") { store.importBackup() }
                            .controlSize(.small)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 11)
        .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1) }
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Close application", systemImage: "power")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var openWindowButton: some View {
        Button {
            openWindow(id: "main")
        } label: {
            Label("Open in separate window", systemImage: "macwindow.on.rectangle")
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}
