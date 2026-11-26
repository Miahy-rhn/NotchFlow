import Foundation

/// Regroupe les objets partagés de l'app. Créé une seule fois par l'AppDelegate,
/// puis passé explicitement aux vues (pas de singleton global).
@MainActor
final class AppContext {
    let preferences: AppPreferences
    let state: NotchState
    let shelf = FileShelfStore()
    let notes = NotesStore()
    let calendar: CalendarModel
    let music = NowPlayingModel(service: SpotifyBridge())
    let timer: TimerModel
    let launchAtLogin = LaunchAtLogin()

    /// Renseigné par l'AppDelegate : ouvre la fenêtre de préférences.
    var openSettings: (() -> Void)?

    init() {
        let preferences = AppPreferences()
        self.preferences = preferences

        let notchState = NotchState(preferences: preferences)
        self.state = notchState

        // Un calendrier désactivé dans les préférences n'est jamais lu.
        let calendar = CalendarModel(
            service: EventKitCalendarService(),
            isActive: preferences.isEnabled(.calendar)
        )
        self.calendar = calendar

        // Le minuteur garde une référence forte au service de notifications.
        let timer = TimerModel(notifier: NotificationService())
        self.timer = timer

        // Le minuteur s'affiche sur l'encoche tant qu'il n'est pas à l'arrêt
        // (et que son widget n'est pas désactivé dans les préférences).
        notchState.setTimerActive(timer.phase != .idle)
        timer.onPhaseChange = { [weak notchState] phase in
            notchState?.setTimerActive(phase != .idle)
        }
        preferences.onChange = { [weak notchState, weak calendar, weak preferences] in
            notchState?.updateBadge()
            guard let calendar, let preferences else { return }
            let wasActive = calendar.isActive
            calendar.isActive = preferences.isEnabled(.calendar)
            if calendar.isActive && !wasActive { calendar.refresh() }
        }
    }
}
