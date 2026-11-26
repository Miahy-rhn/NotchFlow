import SwiftUI

/// Bouton en forme de pilule avec des couleurs explicites : lisible sur le fond noir du panneau,
/// quel que soit le thème macOS (les styles système `.bordered*` avec teinte blanche ne le sont pas).
struct NookPillStyle: ButtonStyle {
    let prominent: Bool
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.16)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
