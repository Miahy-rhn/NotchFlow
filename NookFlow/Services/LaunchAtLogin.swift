import Foundation
import Observation
import ServiceManagement

/// Lancement de NookFlow à l'ouverture de session, via l'API publique `SMAppService` (macOS 13+).
/// L'état n'est pas enregistré par NookFlow : c'est macOS qui fait foi.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init() {
        status = SMAppService.mainApp.status
    }

    /// Activé, ou en attente d'approbation de l'utilisateur dans les Réglages Système.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setOn(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Impossible de modifier le lancement à la connexion : \(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
