import SwiftUI

/// Contenu du panneau étendu : une barre d'onglets, puis le widget sélectionné.
/// Seuls les widgets activés dans les préférences sont affichés, dans l'ordre choisi.
struct ExpandedView: View {
    let context: AppContext

    var body: some View {
        let state = context.state
        let visible = context.preferences.visibleWidgets
        // Si le widget sélectionné a été désactivé, on se rabat sur le premier widget actif.
        let current = context.preferences.resolved(state.selectedWidget)

        VStack(spacing: 8) {
            tabBar(visible: visible, current: current)

            context.widgets.view(for: current, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, state.geometry.notchHeight + 6) // sous la zone de l'encoche
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        // Le fond du panneau est toujours sombre : on force les contrôles en mode sombre.
        .environment(\.colorScheme, .dark)
        .onChange(of: current) { _, newValue in
            if state.selectedWidget != newValue { state.select(newValue) }
        }
    }

    private func tabBar(visible: [WidgetID], current: WidgetID) -> some View {
        let state = context.state

        return HStack(spacing: 4) {
            ForEach(visible) { widget in
                let isSelected = current == widget
                Button {
                    state.select(widget)
                } label: {
                    Label(widget.title, systemImage: widget.symbol)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.16 : 0)))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            Spacer(minLength: 8)

            // Note épinglée : toujours visible (si le widget Notes est activé), un clic l'ouvre.
            if context.preferences.isEnabled(.notes), let pinned = context.notes.pinnedNote {
                Button {
                    context.notes.select(pinned.id)
                    state.select(.notes)
                } label: {
                    Label(pinned.title, systemImage: "pin.fill")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("Note épinglée")
                .accessibilityLabel("Note épinglée : \(pinned.title)")
            }

            // Sans fermeture automatique, il faut un moyen visible de réduire le panneau.
            if !context.preferences.autoClose {
                Button {
                    state.collapse()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Réduire le panneau")
                .accessibilityLabel("Réduire le panneau")
            }
        }
    }
}
