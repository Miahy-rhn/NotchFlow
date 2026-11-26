import AppKit

/// Panneau sans bordure qui ne vole jamais le focus de l'application active.
///
/// Par défaut il ne peut pas devenir « key » (fenêtre qui reçoit le clavier). Il ne le devient
/// que sur demande explicite, pour taper dans une note, puis redevient inerte.
final class NotchPanel: NSPanel {
    var allowsKeyboardInput = false
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Juste au-dessus de la barre de menus, pour pouvoir se superposer à la zone de l'encoche.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        // Sans animation d'apparition/disparition de fenêtre : le « masquer puis réafficher »
        // utilisé pour rendre le clavier à l'app précédente devenait un clignotement visible.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKeyboardInput }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
