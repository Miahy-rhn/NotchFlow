import SwiftUI

/// Ce qu'un widget doit savoir faire pour s'intégrer au panneau.
/// Pour en ajouter un : un nouveau cas dans `WidgetID` (titre, icône, couleurs), une classe qui
/// adopte ce protocole, et son ajout dans la liste de `AppContext`. Rien d'autre.
@MainActor
protocol NookWidget: AnyObject {
    var id: WidgetID { get }
    /// Vrai si le widget a besoin du clavier (saisie de texte). Le panneau ne le prend alors
    /// qu'après un clic explicite dans le widget.
    var wantsKeyboard: Bool { get }

    /// Le panneau va s'ouvrir : l'occasion de rafraîchir des données. Appelé seulement si le
    /// widget est activé dans les préférences.
    func panelWillExpand()
    /// Le widget vient d'être activé ou désactivé dans les préférences (appelé à chaque
    /// changement de préférence : doit être sans effet si l'état n'a pas changé).
    func enabledChanged(_ enabled: Bool)

    func makeView(state: NotchState) -> AnyView
    /// Fond particulier de l'onglet, sinon le fond d'ambiance standard est utilisé.
    func backdrop(notchHeight: CGFloat) -> AnyView?
}

extension NookWidget {
    var wantsKeyboard: Bool { false }
    func panelWillExpand() {}
    func enabledChanged(_ enabled: Bool) {}
    func backdrop(notchHeight: CGFloat) -> AnyView? { nil }
}

/// Liste des widgets de l'app. Remplace les `switch` et les cas particuliers qui étaient
/// répartis dans la fenêtre, la vue étendue et le contexte.
@MainActor
final class WidgetRegistry {
    private let widgets: [WidgetID: NookWidget]

    init(_ list: [NookWidget]) {
        var map: [WidgetID: NookWidget] = [:]
        for widget in list {
            precondition(map[widget.id] == nil, "Widget enregistré deux fois : \(widget.id)")
            map[widget.id] = widget
        }
        widgets = map
    }

    /// Les cas de `WidgetID` qui n'ont pas de widget (doit être vide : voir AppContext).
    var missingWidgets: [WidgetID] { WidgetID.allCases.filter { widgets[$0] == nil } }

    var keyboardWidgets: Set<WidgetID> {
        Set(widgets.values.filter { $0.wantsKeyboard }.map { $0.id })
    }

    func view(for id: WidgetID, state: NotchState) -> AnyView {
        widgets[id]?.makeView(state: state) ?? AnyView(EmptyView())
    }

    func backdrop(for id: WidgetID, notchHeight: CGFloat) -> AnyView? {
        widgets[id]?.backdrop(notchHeight: notchHeight)
    }

    func panelWillExpand(isEnabled: (WidgetID) -> Bool) {
        for id in WidgetID.allCases where isEnabled(id) { widgets[id]?.panelWillExpand() }
    }

    func syncEnabled(isEnabled: (WidgetID) -> Bool) {
        for id in WidgetID.allCases { widgets[id]?.enabledChanged(isEnabled(id)) }
    }
}
