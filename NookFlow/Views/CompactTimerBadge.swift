import SwiftUI

/// Minuteur en miniature, affiché de part et d'autre de l'encoche quand le panneau est réduit :
/// une icône à gauche, le temps restant à droite.
struct CompactTimerBadge: View {
    let timer: TimerModel
    let geometry: NotchGeometry

    var body: some View {
        Group {
            if geometry.hasNotch {
                // Largeur visible de chaque côté de l'encoche.
                let side = (geometry.compactSize(withBadge: true).width - geometry.notchWidth) / 2
                HStack(spacing: 0) {
                    icon.frame(width: side)
                    Spacer(minLength: geometry.notchWidth)
                    timeText.frame(width: side)
                }
            } else {
                HStack(spacing: 6) {
                    icon
                    timeText
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Parties

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var timeText: some View {
        switch timer.phase {
        case .running:
            // Ne tourne que pendant que le minuteur compte (rafraîchissement 2 fois par seconde).
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                label(TimerModel.format(timer.remaining(at: context.date)))
            }
        case .paused(let remaining):
            label(TimerModel.format(remaining))
        case .finished:
            label("Fin")
        case .idle:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var symbol: String {
        switch timer.phase {
        case .paused: "pause.fill"
        case .finished: "bell.fill"
        default: "timer"
        }
    }

    private var color: Color {
        switch timer.phase {
        case .running: .white
        case .paused: .white.opacity(0.6)
        case .finished: .orange
        case .idle: .clear
        }
    }

    private var accessibilityText: String {
        switch timer.phase {
        case .running: "Minuteur en cours"
        case .paused(let remaining): "Minuteur en pause, \(TimerModel.format(remaining)) restant"
        case .finished: "Minuteur terminé"
        case .idle: ""
        }
    }
}
