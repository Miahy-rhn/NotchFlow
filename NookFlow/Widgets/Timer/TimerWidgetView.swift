import SwiftUI

struct TimerWidgetView: View {
    let timer: TimerModel

    private static let presets = [1, 5, 10, 25]

    var body: some View {
        HStack(spacing: 28) {
            VStack(spacing: 4) {
                timeLabel
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            .frame(minWidth: 170)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 12) {
                controls
                if timer.phase == .idle { durationPicker }
                if timer.notificationsDenied {
                    Text("Notifications désactivées : pas d'alerte à la fin. Autorise-les dans Réglages Système.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Affichage du temps

    /// Le `TimelineView` ne tourne que pendant que le minuteur compte ET que le panneau est ouvert.
    @ViewBuilder
    private var timeLabel: some View {
        if case .running = timer.phase {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                clock(timer.remaining(at: context.date))
            }
        } else {
            clock(timer.remaining(at: .now))
        }
    }

    private func clock(_ seconds: TimeInterval) -> some View {
        Text(TimerModel.format(seconds))
            .font(.system(size: 46, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(timer.phase == .finished ? Color.orange : Color.white)
    }

    private var statusText: String {
        switch timer.phase {
        case .idle: return "Prêt"
        case .running: return "En cours"
        case .paused: return "En pause"
        case .finished: return "Terminé"
        }
    }

    private var statusColor: Color {
        timer.phase == .finished ? .orange : .white.opacity(0.55)
    }

    // MARK: - Commandes

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch timer.phase {
            case .idle:
                primaryButton("Démarrer", systemImage: "play.fill") { timer.start() }
            case .running:
                primaryButton("Pause", systemImage: "pause.fill") { timer.pause() }
                secondaryButton("Réinitialiser") { timer.reset() }
            case .paused:
                primaryButton("Reprendre", systemImage: "play.fill") { timer.resume() }
                secondaryButton("Réinitialiser") { timer.reset() }
            case .finished:
                primaryButton("Réinitialiser", systemImage: "arrow.counterclockwise") { timer.reset() }
            }
        }
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(NookPillStyle(prominent: true))
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(NookPillStyle(prominent: false))
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { minutes in
                    let isSelected = timer.duration == TimeInterval(minutes * 60)
                    Button("\(minutes) min") { timer.setDuration(minutes: minutes) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.2 : 0.08)))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Stepper(value: minutesBinding, in: 1...180) {
                Text("Personnalisée : \(minutesBinding.wrappedValue) min")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityLabel("Durée personnalisée en minutes")
        }
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { Int(timer.duration / 60) },
            set: { timer.setDuration(minutes: $0) }
        )
    }
}
