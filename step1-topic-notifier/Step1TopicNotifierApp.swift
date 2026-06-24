import AppKit
import SwiftUI
import UserNotifications

@main
struct Step1TopicNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    @AppStorage(NotificationManager.UserDefaultsKeys.isActive) private var isActive = false
    @AppStorage(NotificationManager.UserDefaultsKeys.intervalMinutes) private var intervalMinutes = 15
    @AppStorage(NotificationManager.UserDefaultsKeys.currentTopicGroups) private var currentTopicGroups = "[]"
    @AppStorage(TopicReviewStore.reviewRecordsDefaultsKey) private var reviewRecordsData = Data()

    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled

    private let notificationManager = NotificationManager.shared
    private let intervals = NotificationManager.allowedIntervalMinutes

    var body: some Scene {
        MenuBarExtra("Step 1 Topics", systemImage: "bell.badge") {
            Text("Step 1 Topic Notifier")

            Button(isActive ? "Stop Notifications" : "Start Notifications") {
                if isActive {
                    notificationManager.stop()
                } else {
                    notificationManager.start()
                }
            }

            Button("Send Notification") {
                notificationManager.sendTestNotification()
            }

            Divider()

            Button("Current Topic: \(currentTopicSummary())") {
                openSettingsWindow()
            }

            Divider()

            Menu("Trouble Topics") {
                let troubleTopics = troubleTopicsForMenu(reviewRecordsData)
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
            }

            Button("Settings...") {
                openSettingsWindow()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: "settings") {
            SettingsView(
                intervalMinutes: $intervalMinutes,
                launchAtLoginEnabled: $launchAtLoginEnabled,
                currentTopicGroups: $currentTopicGroups,
                notificationManager: notificationManager,
                intervals: intervals
            )
        }
        .defaultSize(width: 380, height: 430)
    }

    private func troubleTopicsForMenu(_ reviewRecordsData: Data) -> [TroubleTopic] {
        _ = reviewRecordsData
        return notificationManager.troubleTopics(limit: 5)
    }

    private func currentTopicSummary() -> String {
        let selectedGroupNames = selectedTopicGroupNames()
        return selectedGroupNames.isEmpty ? "All Topics" : selectedGroupNames.joined(separator: ", ")
    }

    private func selectedTopicGroupNames() -> [String] {
        guard let data = currentTopicGroups.data(using: .utf8),
              let selectedGroupNames = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return selectedGroupNames
    }

    private func openSettingsWindow() {
        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
        openWindow(id: "settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @Binding var intervalMinutes: Int
    @Binding var launchAtLoginEnabled: Bool
    @Binding var currentTopicGroups: String

    let notificationManager: NotificationManager
    let intervals: [Int]

    var body: some View {
        Form {
            Picker("Interval", selection: $intervalMinutes) {
                ForEach(intervals, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .onChange(of: intervalMinutes) { newValue in
                notificationManager.updateInterval(minutes: newValue)
            }

            Toggle("Start at Login", isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                    launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
                }
            ))

            Section("Current Topics") {
                Toggle("All Topics", isOn: Binding(
                    get: { selectedTopicGroupNames().isEmpty },
                    set: { newValue in
                        if newValue {
                            notificationManager.updateCurrentTopicGroups([])
                        }
                    }
                ))

                ForEach(notificationManager.topicGroups) { group in
                    Toggle(group.name, isOn: topicGroupBinding(for: group.name))
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 340, minHeight: 360)
    }

    private func topicGroupBinding(for groupName: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedTopicGroupNames().contains(groupName)
            },
            set: { isSelected in
                var selectedGroupNames = selectedTopicGroupNames()

                if isSelected {
                    selectedGroupNames.append(groupName)
                } else {
                    selectedGroupNames.removeAll { $0 == groupName }
                }

                notificationManager.updateCurrentTopicGroups(selectedGroupNames)
            }
        )
    }

    private func selectedTopicGroupNames() -> [String] {
        guard let data = currentTopicGroups.data(using: .utf8),
              let selectedGroupNames = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return selectedGroupNames
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
