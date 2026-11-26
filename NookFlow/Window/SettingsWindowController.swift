import AppKit
import SwiftUI

/// Fenêtre de préférences. NookFlow n'a pas d'icône dans le Dock, donc on ouvre la fenêtre
/// à la main (plus fiable que la scène `Settings` de SwiftUI pour une app de barre de menus).
@MainActor
final class SettingsWindowController {
    private let context: AppContext
    private var window: NSWindow?

    init(context: AppContext) {
        self.context = context
    }

    func show() {
        if window == nil { window = makeWindow() }
        // La fenêtre de réglages a besoin du focus clavier : on active l'app pour ce temps-là.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView(preferences: context.preferences, launchAtLogin: context.launchAtLogin)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Préférences de NookFlow"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false // on la garde pour la rouvrir instantanément
        window.setContentSize(NSSize(width: 520, height: 640))
        window.center()
        return window
    }
}
