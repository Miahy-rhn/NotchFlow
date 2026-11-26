import SwiftUI

/// Couleurs d'ambiance de chaque widget (deux teintes voisines pour un dégradé doux).
extension WidgetID {
    var ambience: (Color, Color) {
        switch self {
        case .files: (Color(red: 0.20, green: 0.55, blue: 1.00), Color(red: 0.10, green: 0.85, blue: 0.85))
        case .notes: (Color(red: 1.00, green: 0.75, blue: 0.20), Color(red: 1.00, green: 0.50, blue: 0.30))
        case .timer: (Color(red: 1.00, green: 0.40, blue: 0.25), Color(red: 0.95, green: 0.20, blue: 0.45))
        case .calendar: (Color(red: 0.55, green: 0.35, blue: 1.00), Color(red: 0.95, green: 0.35, blue: 0.75))
        case .music: (Color(red: 0.15, green: 0.80, blue: 0.45), Color(red: 0.10, green: 0.55, blue: 0.70))
        }
    }
}

/// Fond discret d'un widget : deux halos de couleur très floutés sur du noir, comme une aurore.
/// Statique (aucune animation en continu) pour ne rien consommer au repos.
struct WidgetBackdrop: View {
    let widget: WidgetID
    let notchHeight: CGFloat

    var body: some View {
        let (first, second) = widget.ambience
        Color.clear
            .overlay {
                GeometryReader { geometry in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    ZStack {
                        Circle().fill(first)
                            .frame(width: w * 0.55, height: w * 0.55)
                            .position(x: w * 0.12, y: h * 0.95)
                        Circle().fill(second)
                            .frame(width: w * 0.50, height: w * 0.50)
                            .position(x: w * 0.92, y: h * 0.30)
                    }
                    .blur(radius: 60)
                    .opacity(0.38)
                }
            }
            // Noir au sommet pour se fondre dans l'encoche.
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: notchHeight + 30)
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
