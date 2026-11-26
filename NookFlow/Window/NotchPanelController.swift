import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    private let context: AppContext
    private let panel: NotchPanel
    private var screen: NSScreen?
    private var transitionTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol? // vit aussi longtemps que l'app, pas besoin de le retirer
    private(set) var isVisible = false

    private var state: NotchState { context.state }

    init(context: AppContext) {
        self.context = context
        self.panel = NotchPanel()

        let hostingView = NSHostingView(rootView: NotchRootView(context: context))
        hostingView.sizingOptions = []      // SwiftUI ne doit pas redimensionner la fenêtre
        hostingView.safeAreaRegions = []    // pas de marge automatique sous l'encoche
        panel.contentView = hostingView

        let state = context.state
        state.onModeChange = { [weak self] mode in
            self?.modeChanged(mode)
        }
        state.onBadgeChange = { [weak self] visible in
            self?.badgeChanged(visible)
        }
        state.setKeyboardAccess = { [weak self] enabled in
            self?.setKeyboardAccess(enabled)
        }
        state.isPointerInsidePanel = { [weak self] in
            guard let self else { return false }
            // « Dedans » = pointeur sur le panneau, ou panneau en cours de saisie.
            return self.panel.frame.contains(NSEvent.mouseLocation) || self.panel.isKeyWindow
        }
        panel.onResignKey = { [weak self] in
            self?.panelDidResignKey()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshScreen() }
        }
    }

    func show() {
        refreshScreen()
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        state.collapse()
        panel.orderOut(nil)
        isVisible = false
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    // MARK: - Clavier

    /// Donne ou retire le clavier au panneau.
    /// - Donner : le panneau devient « key » SANS activer NookFlow (style `.nonactivatingPanel`),
    ///   comme la barre de Spotlight.
    /// - Retirer : on masque puis réaffiche le panneau, ce qui rend le clavier à l'app précédente.
    private func setKeyboardAccess(_ enabled: Bool) {
        guard isVisible else { return }
        if enabled {
            panel.allowsKeyboardInput = true
            panel.makeKey()
        } else {
            panel.allowsKeyboardInput = false
            if panel.isKeyWindow {
                // Masquer puis réafficher dans le même tour de boucle : rien n'est dessiné entre les deux.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
                panel.displayIfNeeded()
            }
        }
    }

    /// Le panneau a perdu le clavier (clic dans une autre app, changement d'onglet…).
    private func panelDidResignKey() {
        panel.allowsKeyboardInput = false
        if !panel.frame.contains(NSEvent.mouseLocation) {
            state.hoverChanged(false) // le panneau pourra se réduire
        }
    }

    // MARK: - Privé

    /// Recalcule l'écran cible et la géométrie (changement de résolution, écran branché/débranché…).
    private func refreshScreen() {
        guard let newScreen = ScreenGeometry.preferredScreen() else { return }
        screen = newScreen
        state.geometry = ScreenGeometry.geometry(for: newScreen)
        applyFrame(for: state.mode)
    }

    private func applyFrame(for mode: NotchState.Mode) {
        guard let screen else { return }
        let size = (mode == .expanded)
            ? state.geometry.expandedSize
            : state.geometry.compactSize(withBadge: state.compactBadgeVisible)
        panel.setFrame(ScreenGeometry.frame(size: size, on: screen), display: true)
    }

    /// Le minuteur apparaît ou disparaît sur l'encoche : la fenêtre change de largeur.
    /// Apparition : la fenêtre s'élargit tout de suite, SwiftUI anime ensuite le contenu.
    /// Disparition : SwiftUI anime d'abord, la fenêtre rétrécit une fois l'animation finie.
    /// Si le panneau est étendu, rien à faire : la bonne taille sera appliquée à la réduction.
    private func badgeChanged(_ visible: Bool) {
        guard state.mode == .compact else { return }
        transitionTask?.cancel()
        if visible {
            applyFrame(for: .compact)
        } else {
            let delay = context.preferences.shrinkDelay
            transitionTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.applyFrame(for: .compact)
            }
        }
    }

    /// Transition en deux phases, pour que l'animation parte toujours de l'encoche.
    ///
    /// Ouverture : d'abord la fenêtre grandit tout de suite (invisible : le contenu SwiftUI est
    /// encore compact et le reste de la fenêtre est transparent), puis un instant plus tard
    /// SwiftUI anime du compact vers l'étendu.
    /// Fermeture : d'abord SwiftUI anime vers le compact, puis une fois l'animation finie
    /// la fenêtre rétrécit, pour ne pas intercepter de clics inutilement.
    private func modeChanged(_ mode: NotchState.Mode) {
        transitionTask?.cancel()
        switch mode {
        case .expanded:
            // Chaque widget activé rafraîchit ses données (fichiers déplacés, calendrier…).
            let preferences = context.preferences
            context.widgets.panelWillExpand(isEnabled: { preferences.isEnabled($0) })
            // Le widget sélectionné a pu être désactivé depuis la dernière ouverture.
            state.resolveSelection()
            applyFrame(for: .expanded)
            transitionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self else { return }
                withAnimation(self.context.preferences.animation) { self.state.isContentExpanded = true }
            }
        case .compact:
            withAnimation(context.preferences.animation) { state.isContentExpanded = false }
            let delay = context.preferences.shrinkDelay
            transitionTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.applyFrame(for: .compact)
                // Une fois fermé, on revient au premier widget si l'utilisateur l'a demandé.
                self.state.resetSelectionAfterClose()
            }
        }
    }
}
