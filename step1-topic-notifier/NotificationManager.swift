import AppKit
import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    static let topicNotificationIdentifier = "step1-topic-notifier.next-topic"
    static let allowedIntervalMinutes = [10, 15, 20, 30, 45, 60]

    private enum NotificationCategory {
        static let topicReview = "step1-topic-notifier.topic-review"
        static let againAction = "step1-topic-notifier.review.again"
        static let soSoAction = "step1-topic-notifier.review.so-so"
        static let goodAction = "step1-topic-notifier.review.good"
    }

    enum UserDefaultsKeys {
        static let isActive = "isActive"
        static let intervalMinutes = "intervalMinutes"
        static let nextFireDate = "nextFireDate"
    }

    private let center = UNUserNotificationCenter.current()
    private let topicStore = TopicStore()
    private let reviewStore = TopicReviewStore()
    private let defaults = UserDefaults.standard

    private var deliveryFollowUpWorkItem: DispatchWorkItem?

    private init() {
        defaults.register(defaults: [
            UserDefaultsKeys.isActive: false,
            UserDefaultsKeys.intervalMinutes: 15,
            UserDefaultsKeys.nextFireDate: 0.0
        ])
        registerNotificationCategories()
    }

    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        print("Notification permission request failed: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        completion?(granted)
                    }
                }

            case .authorized, .provisional:
                DispatchQueue.main.async {
                    completion?(true)
                }

            case .denied:
                DispatchQueue.main.async {
                    completion?(false)
                }

            @unknown default:
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }
    }

    func start() {
        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }

            guard granted else {
                self.defaults.set(false, forKey: UserDefaultsKeys.isActive)
                return
            }

            self.defaults.set(true, forKey: UserDefaultsKeys.isActive)
            self.scheduleNextTopicNotification()
        }
    }

    func stop() {
        defaults.set(false, forKey: UserDefaultsKeys.isActive)
        defaults.removeObject(forKey: UserDefaultsKeys.nextFireDate)
        cancelDeliveryFollowUp()
        center.removePendingNotificationRequests(withIdentifiers: [Self.topicNotificationIdentifier])
    }

    func updateInterval(minutes: Int) {
        guard Self.allowedIntervalMinutes.contains(minutes) else { return }

        defaults.set(minutes, forKey: UserDefaultsKeys.intervalMinutes)

        if defaults.bool(forKey: UserDefaultsKeys.isActive) {
            scheduleNextTopicNotification()
        }
    }

    func resumeIfNeeded() {
        guard defaults.bool(forKey: UserDefaultsKeys.isActive) else { return }

        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }

            guard granted else {
                self.defaults.set(false, forKey: UserDefaultsKeys.isActive)
                return
            }

            self.center.getPendingNotificationRequests { requests in
                let hasScheduledTopic = requests.contains {
                    $0.identifier == Self.topicNotificationIdentifier
                }

                DispatchQueue.main.async {
                    if hasScheduledTopic {
                        self.scheduleDeliveryFollowUp(after: self.remainingTimeUntilNextFire)
                    } else {
                        self.scheduleNextTopicNotification()
                    }
                }
            }
        }
    }

    func notificationDelivered() {
        guard defaults.bool(forKey: UserDefaultsKeys.isActive) else { return }
        scheduleNextTopicNotification()
    }

    func sendTestNotification() {
        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self, granted else { return }

            let topic = self.reviewStore.nextTopic(from: self.topicStore.topics)
            self.sendImmediateReviewNotification(for: topic, identifierPrefix: "test")
        }
    }

    func sendReviewNotification(for topic: String) {
        guard topicStore.topics.contains(topic) else { return }

        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self, granted else { return }
            self.sendImmediateReviewNotification(for: topic, identifierPrefix: "manual")
        }
    }

    func troubleTopics(limit: Int) -> [TroubleTopic] {
        reviewStore.troubleTopics(from: topicStore.topics, limit: limit)
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        let topic = content.userInfo["topic"] as? String ?? content.title

        guard let rating = rating(for: response.actionIdentifier) else {
            return
        }

        reviewStore.recordReview(for: topic, rating: rating)

        if rating.opensSearch {
            openGoogleSearch(for: topic)
        }

        if defaults.bool(forKey: UserDefaultsKeys.isActive) {
            scheduleNextTopicNotification()
        }
    }

    private var currentInterval: TimeInterval {
        let minutes = defaults.integer(forKey: UserDefaultsKeys.intervalMinutes)
        let validMinutes = Self.allowedIntervalMinutes.contains(minutes) ? minutes : 15
        return TimeInterval(validMinutes * 60)
    }

    private var remainingTimeUntilNextFire: TimeInterval {
        let nextFireDate = defaults.double(forKey: UserDefaultsKeys.nextFireDate)

        guard nextFireDate > 0 else {
            return currentInterval
        }

        return max(1, nextFireDate - Date().timeIntervalSince1970)
    }

    private func scheduleNextTopicNotification() {
        guard defaults.bool(forKey: UserDefaultsKeys.isActive) else { return }

        cancelDeliveryFollowUp()
        center.removePendingNotificationRequests(withIdentifiers: [Self.topicNotificationIdentifier])

        let topic = reviewStore.nextTopic(from: topicStore.topics)
        let content = notificationContent(for: topic)
        let interval = currentInterval
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.topicNotificationIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { [weak self] error in
            if let error {
                print("Topic notification scheduling failed: \(error.localizedDescription)")
                return
            }

            DispatchQueue.main.async {
                self?.defaults.set(Date().timeIntervalSince1970 + interval, forKey: UserDefaultsKeys.nextFireDate)
                self?.scheduleDeliveryFollowUp(after: interval)
            }
        }
    }

    private func notificationContent(for topic: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = topic
        content.body = "Talk through this from memory."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.topicReview
        content.userInfo = ["topic": topic]
        return content
    }

    private func sendImmediateReviewNotification(for topic: String, identifierPrefix: String) {
        let content = notificationContent(for: topic)
        let request = UNNotificationRequest(
            identifier: "step1-topic-notifier.\(identifierPrefix).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                print("Review notification scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    private func registerNotificationCategories() {
        let againAction = UNNotificationAction(
            identifier: NotificationCategory.againAction,
            title: "Again",
            options: []
        )
        let soSoAction = UNNotificationAction(
            identifier: NotificationCategory.soSoAction,
            title: "So-So",
            options: []
        )
        let goodAction = UNNotificationAction(
            identifier: NotificationCategory.goodAction,
            title: "Good",
            options: []
        )
        let topicReviewCategory = UNNotificationCategory(
            identifier: NotificationCategory.topicReview,
            actions: [againAction, soSoAction, goodAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([topicReviewCategory])
    }

    private func rating(for actionIdentifier: String) -> TopicReviewRating? {
        switch actionIdentifier {
        case NotificationCategory.againAction:
            return .again
        case NotificationCategory.soSoAction, UNNotificationDefaultActionIdentifier:
            return .soSo
        case NotificationCategory.goodAction:
            return .good
        default:
            return nil
        }
    }

    // macOS does not provide a general "local notification fired" callback for every
    // app state, so this running menu bar app keeps the loop moving with a follow-up.
    private func scheduleDeliveryFollowUp(after interval: TimeInterval) {
        cancelDeliveryFollowUp()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.notificationDelivered()
        }

        deliveryFollowUpWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval + 1, execute: workItem)
    }

    private func cancelDeliveryFollowUp() {
        deliveryFollowUpWorkItem?.cancel()
        deliveryFollowUpWorkItem = nil
    }

    private func openGoogleSearch(for topic: String) {
        let query = "\(topic) USMLE Step 1"
        let encodedQuery = query
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)?
            .replacingOccurrences(of: "%20", with: "+") ?? query

        guard let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
