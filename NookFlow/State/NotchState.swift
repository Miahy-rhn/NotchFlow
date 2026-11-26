import Foundation
import Observation

/// Les widgets disponibles dans le panneau étendu.
enum WidgetID: String, CaseIterable, Identifiable {
    case files
    case notes
    case timer
    case calendar
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Fichiers"
        case .notes: "Notes"
        case .timer: "Minuteur"
        case .calendar: "Calendrier"
        case .music: "Musique"
        }
    }

    var symbol: String {
        switch self {
        case .files: "tray.full"
        case .notes: "note.text"
        case .timer: "timer"
        case .calendar: "calendar"
        case .music: "music.note"
        }
    }
}

@MainActor
@Observable
final class NotchState {
    enum Mode {
        case compact
        case expanded
    }

    @ObservationIgnored let preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    /// État logique : sert au contrôleur à dimensionner la fenêtre AppKit.
    var mode: Mode = .compact {
        didSet {
            guard oldValue != mode else { return }
            onModeChange?(mode)
            // En se réduisant, le panneau rend toujours le clavier à l'app active.
            if mode == .compact { setKeyboardAccess?(false) }
        }
    }

    /// État visuel : ce que SwiftUI dessine. Il est piloté par le contrôleur de fenêtre,
    /// qui l'anime une fois la fenêtre redimensionnée (voir NotchPanelController).
    var isContentExpanded = false

    /// Vrai quand un glisser-déposer survole le panneau.
    var isDropTargeted = false

    var selectedWidget: WidgetID = .files

    /// Widgets qui ont besoin du clavier (renseigné depuis le registre par AppContext).
    @ObservationIgnored var keyboardWidgets: Set<WidgetID> = []

    /// Vrai quand le panneau compact doit afficher le minuteur (en cours, en pause ou terminé)
    /// et que le widget Minuteur est activé dans les préférences.
    var compactBadgeVisible = false {
        didSet {
            if oldValue != compactBadgeVisible { onBadgeChange?(compactBadgeVisible) }
        }
    }

    /// Incrémenté à chaque demande de clavier : les vues s'en servent pour reprendre le focus.
    private(set) var keyboardGrantCount = 0

    var geometry: NotchGeometry = .fallback

    /// Appelé par le contrôleur de fenêtre pour redimensionner le panneau AppKit.
    @ObservationIgnored var onModeChange: ((Mode) -> Void)?
    /// Appelé quand le badge compact apparaît ou disparaît (la fenêtre doit alors changer de largeur).
    @ObservationIgnored var onBadgeChange: ((Bool) -> Void)?
    /// Renseigné par le contrôleur : donne ou retire l'accès clavier au panneau.
    @ObservationIgnored var setKeyboardAccess: ((Bool) -> Void)?
    /// Renseigné par le contrôleur : indique si le pointeur est encore dans la fenêtre
    /// ou si le panneau est en cours de saisie.
    @ObservationIgnored var isPointerInsidePanel: (() -> Bool)?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var timerActive = false

    func expand() { mode = .expanded }
    func collapse() { mode = .compact }
    func toggle() { mode = (mode == .compact) ? .expanded : .compact }

    // MARK: - Badge du minuteur

    func setTimerActive(_ active: Bool) {
        timerActive = active
        updateBadge()
    }

    /// À rappeler quand les préférences changent (le widget Minuteur a pu être désactivé).
    func updateBadge() {
        compactBadgeVisible = timerActive && preferences.isEnabled(.timer)
    }

    // MARK: - Widgets et clavier

    func select(_ widget: WidgetID) {
        selectedWidget = widget
        if keyboardWidgets.contains(widget) {
            requestKeyboard()
        } else {
            setKeyboardAccess?(false)
        }
    }

    /// Le clavier n'est jamais demandé automatiquement (sinon le simple passage de la souris
    /// volerait le focus) : uniquement après un clic explicite dans un widget qui le demande (Notes).
    func requestKeyboard() {
        guard keyboardWidgets.contains(selectedWidget) else { return }
        keyboardGrantCount &+= 1
        setKeyboardAccess?(true)
    }

    // MARK: - Survol

    /// Ouverture et fermeture au survol, avec les délais des préférences.
    /// - `forceOpen` : pendant un glisser-déposer, le panneau s'ouvre même en mode « clic uniquement ».
    func hoverChanged(_ isInside: Bool, forceOpen: Bool = false) {
        hoverTask?.cancel()

        if isInside, mode == .compact, preferences.openTrigger == .clickOnly, !forceOpen { return }
        if !isInside, !preferences.autoClose { return }

        let delay = isInside ? preferences.hoverOpenDelay : preferences.closeDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }

            if isInside {
                self.mode = .expanded
                return
            }

            // Le pointeur peut encore être dans la fenêtre alors que SwiftUI le croit dehors
            // (coins arrondis, fin d'un glisser-déposer), ou l'utilisateur est en train de saisir
            // une note. On attend que ce soit vraiment fini.
            while self.isPointerInsidePanel?() == true {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            self.mode = .compact
        }
    }
}
