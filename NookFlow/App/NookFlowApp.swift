import SwiftUI

@main
struct NookFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NookFlow", systemImage: "rectangle.topthird.inset.filled") {
            Button("Afficher / Masquer le panneau") {
                appDelegate.panelController?.toggleVisibility()
            }
            Button("Ouvrir / Réduire") {
                appDelegate.state.toggle()
            }
            Divider()
            Button("Préférences…") {
                appDelegate.showSettings()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quitter NookFlow") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
