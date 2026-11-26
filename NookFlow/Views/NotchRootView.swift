import SwiftUI

struct NotchRootView: View {
    let context: AppContext

    var body: some View {
        let state = context.state
        let preferences = context.preferences
        // Le dessin suit l'état visuel (isContentExpanded), animé par le contrôleur de fenêtre.
        let isExpanded = state.isContentExpanded
        let size = isExpanded
            ? state.geometry.expandedSize
            : state.geometry.compactSize(withBadge: state.compactBadgeVisible)
        let radius: CGFloat = isExpanded ? 26 : 12
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius
        )

        ZStack(alignment: .top) {
            // Toujours noir au repos, pour se fondre dans l'encoche.
            shape.fill(.black)

            // Panneau ouvert : le thème apparaît en fondu, avec du noir sur la hauteur de l'encoche.
            shape
                .fill(themeGradient(preferences.theme, height: size.height, notchHeight: state.geometry.notchHeight))
                .opacity(isExpanded ? 1 : 0)

            // Fond de l'onglet actif : celui du widget s'il en propose un (pochette de la Musique),
            // sinon des halos de couleur propres à chaque widget.
            if isExpanded {
                if let backdrop = context.widgets.backdrop(for: state.selectedWidget, notchHeight: state.geometry.notchHeight) {
                    backdrop.transition(.opacity)
                } else {
                    WidgetBackdrop(widget: state.selectedWidget, notchHeight: state.geometry.notchHeight)
                        .id(state.selectedWidget)
                        .transition(.opacity)
                }
            }

            if isExpanded {
                ExpandedView(context: context)
                    .transition(.opacity)
            } else if state.compactBadgeVisible {
                CompactTimerBadge(timer: context.timer, geometry: state.geometry)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        // Le badge élargit ou rétrécit le panneau compact en douceur.
        .animation(preferences.animation, value: state.compactBadgeVisible)
        .animation(.easeInOut(duration: 0.35), value: context.music.artwork != nil)
        .animation(.easeInOut(duration: 0.35), value: state.selectedWidget)
        .clipShape(shape)
        .contentShape(shape)
        .onHover { state.hoverChanged($0) }
        .onTapGesture {
            if state.mode == .compact {
                // Un clic sur le minuteur ouvre directement l'onglet Minuteur.
                if state.compactBadgeVisible { state.selectedWidget = .timer }
                state.expand()
            }
        }
        // Dépôt de fichiers : pendant un glisser, le survol classique ne s'active pas,
        // c'est donc `isTargeted` qui ouvre le panneau (et le referme si on s'éloigne).
        .dropDestination(
            for: URL.self,
            action: { urls, _ in
                // Le dépôt de fichiers fonctionne même si le widget Fichiers est masqué des onglets :
                // on l'accepte seulement s'il est activé.
                guard preferences.isEnabled(.files) else { return false }
                let accepted = context.shelf.add(urls)
                if accepted { state.select(.files) } // montre où les fichiers sont arrivés
                return accepted
            },
            isTargeted: { targeted in
                state.isDropTargeted = targeted
                state.hoverChanged(targeted && preferences.isEnabled(.files), forceOpen: true)
            }
        )
        // Accès de secours si l'icône de la barre de menus est cachée par l'encoche.
        .contextMenu {
            Button(state.mode == .compact ? "Ouvrir" : "Réduire") { state.toggle() }
            Button("Préférences…") { context.openSettings?() }
            Divider()
            Button("Quitter NookFlow") { NSApplication.shared.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    /// Dégradé du panneau ouvert : noir sur la hauteur de l'encoche, puis la couleur du thème.
    private func themeGradient(_ theme: NookTheme, height: CGFloat, notchHeight: CGFloat) -> LinearGradient {
        let safeHeight = max(height, 1)
        let notchStop = min(1, notchHeight / safeHeight)
        let blendStop = min(1, (notchHeight + 28) / safeHeight)
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: notchStop),
                .init(color: theme.color, location: blendStop)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
