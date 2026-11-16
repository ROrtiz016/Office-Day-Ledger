import SwiftUI
import UserNotifications
import AppKit
import Darwin

@main
struct OfficeDayCounterApp: App {
    @StateObject private var store: OfficeDayStore

    init() {
        SingleInstanceGuard.enforce()
        _store = StateObject(wrappedValue: OfficeDayStore.shared)
        UNUserNotificationCenter.current().delegate = OfficeDayNotificationDelegate.shared
        OfficeDayNotificationDelegate.shared.store = OfficeDayStore.shared
        let countAction = UNNotificationAction(identifier: "COUNT_OFFICE_DAY", title: "Count today")
        let skipAction = UNNotificationAction(identifier: "SKIP_OFFICE_DAY", title: "Not today", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: "OFFICE_DAY_CONFIRMATION",
            actions: [countAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    var body: some Scene {
        MenuBarExtra("Office Days", systemImage: store.todayIsMarked ? "building.2.fill" : "building.2", isInserted: .constant(true)) {
            DashboardView(store: store)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Office Day Counter", id: "main") {
            DashboardView(store: store)
        }
    }
}

private enum SingleInstanceGuard {
    static func enforce() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let otherInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessID }

        guard let otherInstance else { return }
        otherInstance.activate(options: [])
        exit(EXIT_SUCCESS)
    }
}

final class OfficeDayNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = OfficeDayNotificationDelegate()
    weak var store: OfficeDayStore?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let dayKey = response.notification.request.content.userInfo["dayKey"] as? String
        let token = response.notification.request.content.userInfo["token"] as? String
        DispatchQueue.main.async { [weak self] in
            guard let self, let dayKey, let token else {
                completionHandler()
                return
            }
            self.store?.handleWiFiNotification(dayKey: dayKey, token: token, count: response.actionIdentifier == "COUNT_OFFICE_DAY")
            completionHandler()
        }
    }
}
