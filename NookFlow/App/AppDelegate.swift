import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let context = AppContext()
    private(set) var panelController: NotchPanelController?
    private var settingsController: SettingsWindowController?

    var state: NotchState { context.state }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pas d'icône dans le Dock, pas de menu d'application.
        NSApp.setActivationPolicy(.accessory)

        context.openSettings = { [weak self] in self?.showSettings() }

        let controller = NotchPanelController(context: context)
        panelController = controller
        controller.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Écrit tout de suite les notes encore en attente d'enregistrement.
        context.notes.flush()
    }

    func showSettings() {
        if settingsController == nil { settingsController = SettingsWindowController(context: context) }
        settingsController?.show()
    }
}
