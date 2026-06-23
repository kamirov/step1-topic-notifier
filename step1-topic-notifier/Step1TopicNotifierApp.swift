import AppKit
import SwiftUI
import UserNotifications

@main
struct Step1TopicNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage(NotificationManager.UserDefaultsKeys.isActive) private var isActive = false
    @AppStorage(NotificationManager.UserDefaultsKeys.intervalMinutes) private var intervalMinutes = 15

    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled

    private let notificationManager = NotificationManager.shared
    private let intervals = [5, 15, 30, 60]

    var body: some Scene {
        MenuBarExtra("Step 1 Topics", systemImage: "bell.badge") {
            Text(isActive ? "Notifications Active" : "Notifications Stopped")

            Button(isActive ? "Stop Notifications" : "Start Notifications") {
                if isActive {
                    notificationManager.stop()
                } else {
                    notificationManager.start()
                }
            }

            Divider()

            Picker("Interval", selection: $intervalMinutes) {
                ForEach(intervals, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .onChange(of: intervalMinutes) { newValue in
                notificationManager.updateInterval(minutes: newValue)
            }

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                    launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
                }
            ))

            Divider()

            Text("Trouble Topics")

            let troubleTopics = notificationManager.troubleTopics(limit: 5)
            if troubleTopics.isEmpty {
                Text("No trouble topics yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(troubleTopics) { troubleTopic in
                    Button("\(troubleTopic.topic) - \(troubleTopic.score)") {
                        notificationManager.sendReviewNotification(for: troubleTopic.topic)
                    }
                }
            }

            Divider()

            Button("Send Test Notification") {
                notificationManager.sendTestNotification()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        NotificationManager.shared.requestAuthorizationIfNeeded()
        NotificationManager.shared.resumeIfNeeded()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == NotificationManager.topicNotificationIdentifier {
            DispatchQueue.main.async {
                NotificationManager.shared.notificationDelivered()
            }
        }

        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationManager.shared.handleNotificationResponse(response)
        completionHandler()
    }
}
