import Foundation
import UserNotifications
import UIKit

extension Notification.Name {
    static let snapCountShortcutNotificationRoute = Notification.Name("snapCountShortcutNotificationRoute")
}

final class ShortcutNotificationService {
    static let shared = ShortcutNotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func notifyUploadResult(_ result: ShortcutUploadResult) async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = result.notificationTitle
        content.body = result.notificationBody
        content.sound = .default
        content.userInfo = ["route": result.route]

        let request = UNNotificationRequest(
            identifier: "jiezi-shortcut-upload-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        try? await center.add(request)
    }
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static var pendingRoute: String?

    static func consumePendingRoute() -> String? {
        let route = pendingRoute
        pendingRoute = nil
        return route
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        Self.pendingRoute = route
        NotificationCenter.default.post(
            name: .snapCountShortcutNotificationRoute,
            object: nil,
            userInfo: ["route": route ?? ""]
        )
    }
}
