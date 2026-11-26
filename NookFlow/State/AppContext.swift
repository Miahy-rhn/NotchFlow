import Foundation

/// Regroupe les objets partagés de l'app. Créé une seule fois par l'AppDelegate,
/// puis passé explicitement aux vues (pas de singleton global).
@MainActor
final class AppContext {
    let preferences: AppPreferences
    let state: NotchState
    let shelf: FileShelfStore
    let notes: NotesStore
    let calendar: CalendarModel
    let music: NowPlayingModel
    let timer: TimerModel
    let widgets: WidgetRegistry
    let launchAtLogin = LaunchAtLogin()

    /// Renseigné par l'AppDelegate : ouvre la fenêtre de préférences.
    var openSettings: (() -> Void)?

    init() {
        let preferences = AppPreferences()
        self.preferences = preferences

        let notchState = NotchState(preferences: preferences)
        self.state = notchState

        let shelf = FileShelfStore()
        self.shelf = shelf
        let notes = NotesStore()
        self.notes = notes
        let music = NowPlayingModel(service: SpotifyBridge())
        self.music = music

        // Un calendrier désactivé dans les préférences n'est jamais lu.
        let calendar = CalendarModel(
            service: EventKitCalendarService(),
            isActive: preferences.isEnabled(.calendar)
        )
        self.calendar = calendar

        // Le minuteur garde une référence forte au service de notifications.
        let timer = TimerModel(notifier: NotificationService())
        self.timer = timer

        // Registre des widgets : c'est lui qui relie chaque modèle à sa vue.
        let registry = WidgetRegistry([
            FilesWidget(store: shelf),
            NotesWidget(store: notes),
            TimerWidget(timer: timer),
            CalendarWidget(model: calendar),
            MusicWidget(model: music)
        ])
        assert(registry.missingWidgets.isEmpty, "Un cas de WidgetID n'a pas de widget : \(registry.missingWidgets)")
        self.widgets = registry
        notchState.keyboardWidgets = registry.keyboardWidgets

        // Le minuteur s'affiche sur l'encoche tant qu'il n'est pas à l'arrêt
        // (et que son widget n'est pas désactivé dans les préférences).
        notchState.setTimerActive(timer.phase != .idle)
        timer.onPhaseChange = { [weak notchState] phase in
            notchState?.setTimerActive(phase != .idle)
        }
        preferences.onChange = { [weak notchState, weak registry, weak preferences] in
            notchState?.updateBadge()
            guard let registry, let preferences else { return }
            registry.syncEnabled(isEnabled: { preferences.isEnabled($0) })
        }
    }
}
