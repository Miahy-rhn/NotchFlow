import AppKit
import Observation
import SwiftUI

/// Comment le panneau s'ouvre depuis l'état réduit.
enum OpenTrigger: String, CaseIterable, Identifiable {
    case hoverOrClick
    case clickOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoverOrClick: "Survol ou clic"
        case .clickOnly: "Clic uniquement"
        }
    }
}

/// Couleur de fond du panneau étendu. Le panneau réduit reste toujours noir pour se fondre
/// dans l'encoche ; en haut, le panneau étendu garde du noir sur la hauteur de l'encoche.
enum NookTheme: String, CaseIterable, Identifiable {
    case black
    case graphite
    case midnight
    case forest
    case plum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Noir"
        case .graphite: "Graphite"
        case .midnight: "Minuit"
        case .forest: "Forêt"
        case .plum: "Prune"
        }
    }

    var color: Color {
        switch self {
        case .black: Color(red: 0, green: 0, blue: 0)
        case .graphite: Color(red: 0.14, green: 0.14, blue: 0.16)
        case .midnight: Color(red: 0.05, green: 0.09, blue: 0.22)
        case .forest: Color(red: 0.04, green: 0.15, blue: 0.11)
        case .plum: Color(red: 0.17, green: 0.07, blue: 0.22)
        }
    }
}

enum AnimationStyle: String, CaseIterable, Identifiable {
    case smooth
    case snappy
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: "Douces"
        case .snappy: "Vives"
        case .none: "Aucune"
        }
    }
}

/// Préférences de l'utilisateur, enregistrées dans UserDefaults dès qu'elles changent.
@MainActor
@Observable
final class AppPreferences {
    // MARK: - Réglages

    /// Ordre de tous les widgets : le premier widget activé s'affiche en priorité.
    var widgetOrder: [WidgetID] { didSet { save() } }
    var disabledWidgets: Set<WidgetID> { didSet { save() } }
    /// Si vrai, le panneau s'ouvre toujours sur le premier widget ; sinon sur le dernier utilisé.
    var openOnFirstWidget: Bool { didSet { save() } }

    var openTrigger: OpenTrigger { didSet { save() } }
    /// Délai (secondes) entre l'arrivée du pointeur et l'ouverture.
    var hoverOpenDelay: Double { didSet { save() } }
    var autoClose: Bool { didSet { save() } }
    /// Délai (secondes) entre le départ du pointeur et la fermeture.
    var closeDelay: Double { didSet { save() } }

    var theme: NookTheme { didSet { save() } }
    var animationStyle: AnimationStyle { didSet { save() } }

    /// Prévenu après chaque modification (sert à recalculer ce qui dépend des réglages).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Valeurs par défaut

    static let defaultHoverOpenDelay = 0.15
    static let defaultCloseDelay = 0.5

    // MARK: - Initialisation

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Ordre : on garde ce qui est enregistré, sans doublon, puis on ajoute les widgets
        // apparus depuis (une mise à jour de l'app peut en ajouter).
        var order: [WidgetID] = []
        for raw in defaults.stringArray(forKey: Keys.order) ?? [] {
            if let widget = WidgetID(rawValue: raw), !order.contains(widget) { order.append(widget) }
        }
        for widget in WidgetID.allCases where !order.contains(widget) { order.append(widget) }
        self.widgetOrder = order

        let disabled = Set((defaults.stringArray(forKey: Keys.disabled) ?? []).compactMap(WidgetID.init(rawValue:)))
        // Garde-fou : au moins un widget doit rester activé.
        self.disabledWidgets = disabled.count >= WidgetID.allCases.count ? [] : disabled

        self.openOnFirstWidget = defaults.object(forKey: Keys.openOnFirst) as? Bool ?? false
        self.openTrigger = OpenTrigger(rawValue: defaults.string(forKey: Keys.trigger) ?? "") ?? .hoverOrClick
        self.hoverOpenDelay = Self.clamp(defaults.object(forKey: Keys.hoverDelay) as? Double ?? Self.defaultHoverOpenDelay, 0.05, 1.0)
        self.autoClose = defaults.object(forKey: Keys.autoClose) as? Bool ?? true
        self.closeDelay = Self.clamp(defaults.object(forKey: Keys.closeDelay) as? Double ?? Self.defaultCloseDelay, 0.2, 3.0)
        self.theme = NookTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .black
        self.animationStyle = AnimationStyle(rawValue: defaults.string(forKey: Keys.animation) ?? "") ?? .smooth
    }

    // MARK: - Widgets

    /// Widgets activés, dans l'ordre choisi.
    var visibleWidgets: [WidgetID] {
        widgetOrder.filter { !disabledWidgets.contains($0) }
    }

    func isEnabled(_ widget: WidgetID) -> Bool { !disabledWidgets.contains(widget) }

    /// Active ou désactive un widget. Le dernier widget actif ne peut pas être désactivé.
    func setEnabled(_ enabled: Bool, for widget: WidgetID) {
        if enabled {
            disabledWidgets.remove(widget)
        } else if visibleWidgets.count > 1 || !isEnabled(widget) {
            disabledWidgets.insert(widget)
        }
    }

    func canDisable(_ widget: WidgetID) -> Bool {
        !isEnabled(widget) || visibleWidgets.count > 1
    }

    func move(_ widget: WidgetID, by offset: Int) {
        guard let index = widgetOrder.firstIndex(of: widget) else { return }
        let target = index + offset
        guard widgetOrder.indices.contains(target) else { return }
        widgetOrder.swapAt(index, target)
    }

    // MARK: - Animations

    /// Animation à utiliser, ou `nil` pour aucune. Respecte « Réduire les animations » de macOS.
    var animation: Animation? {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return nil }
        switch animationStyle {
        case .smooth: return .spring(response: 0.38, dampingFraction: 0.82)
        case .snappy: return .spring(response: 0.26, dampingFraction: 0.9)
        case .none: return nil
        }
    }

    /// Temps à attendre avant de rétrécir la fenêtre, une fois l'animation de fermeture terminée.
    var shrinkDelay: Duration {
        guard animation != nil else { return .zero }
        return animationStyle == .snappy ? .milliseconds(320) : .milliseconds(450)
    }

    // MARK: - Restauration

    /// Remet tous les réglages à leur valeur d'origine.
    func resetToDefaults() {
        widgetOrder = WidgetID.allCases
        disabledWidgets = []
        openOnFirstWidget = false
        openTrigger = .hoverOrClick
        hoverOpenDelay = Self.defaultHoverOpenDelay
        autoClose = true
        closeDelay = Self.defaultCloseDelay
        theme = .black
        animationStyle = .smooth
    }

    // MARK: - Persistance

    private enum Keys {
        static let order = "prefs.widgetOrder"
        static let disabled = "prefs.disabledWidgets"
        static let openOnFirst = "prefs.openOnFirstWidget"
        static let trigger = "prefs.openTrigger"
        static let hoverDelay = "prefs.hoverOpenDelay"
        static let autoClose = "prefs.autoClose"
        static let closeDelay = "prefs.closeDelay"
        static let theme = "prefs.theme"
        static let animation = "prefs.animation"
    }

    private func save() {
        defaults.set(widgetOrder.map(\.rawValue), forKey: Keys.order)
        defaults.set(disabledWidgets.map(\.rawValue).sorted(), forKey: Keys.disabled)
        defaults.set(openOnFirstWidget, forKey: Keys.openOnFirst)
        defaults.set(openTrigger.rawValue, forKey: Keys.trigger)
        defaults.set(hoverOpenDelay, forKey: Keys.hoverDelay)
        defaults.set(autoClose, forKey: Keys.autoClose)
        defaults.set(closeDelay, forKey: Keys.closeDelay)
        defaults.set(theme.rawValue, forKey: Keys.theme)
        defaults.set(animationStyle.rawValue, forKey: Keys.animation)
        onChange?()
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
