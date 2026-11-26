import Foundation
import UserNotifications

/// Ce dont le minuteur a besoin pour prévenir l'utilisateur.
/// Un protocole simple permet de le remplacer par un faux objet dans les tests.
@MainActor
protocol TimerNotifying: AnyObject {
    /// Demande l'autorisation si elle n'a jamais été demandée. Renvoie `true` si on peut notifier.
    func requestAuthorizationIfNeeded() async -> Bool
    func scheduleTimerEnd(at date: Date)
    func cancelTimerEnd()
}

/// Notifications locales via UserNotifications : aucun serveur, aucune donnée envoyée.
@MainActor
final class NotificationService: NSObject, TimerNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "nookflow.timer.end"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    func scheduleTimerEnd(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Minuteur terminé"
        content.body = "Le compte à rebours NookFlow est arrivé à zéro."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancelTimerEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // Affiche la bannière même si NookFlow est considérée comme l'app active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
