import AppKit
import Foundation
import Observation

/// Minuteur basé sur une *date de fin* et non sur un compteur décrémenté :
/// le temps restant est toujours `fin - maintenant`, donc il reste exact même si
/// l'interface est fermée, si les mises à jour visuelles s'arrêtent ou si le Mac se met en veille.
@MainActor
@Observable
final class TimerModel {
    enum Phase: Equatable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    private(set) var phase: Phase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    /// Durée choisie (en secondes), utilisée au démarrage et à la réinitialisation.
    private(set) var duration: TimeInterval = 5 * 60
    /// Vrai si l'utilisateur a refusé les notifications : le minuteur marche, mais sans alerte système.
    private(set) var notificationsDenied = false

    /// Prévenu à chaque changement d'état (sert à afficher le minuteur sur l'encoche).
    @ObservationIgnored var onPhaseChange: ((Phase) -> Void)?

    @ObservationIgnored private let notifier: TimerNotifying
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private static let storageKey = "timer.snapshot"

    init(
        notifier: TimerNotifying,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.notifier = notifier
        self.defaults = defaults
        self.now = now
        restore()
    }

    // MARK: - Lecture

    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .idle: return duration
        case .running(let end): return max(0, end.timeIntervalSince(date))
        case .paused(let remaining): return remaining
        case .finished: return 0
        }
    }

    /// « 4:07 » ou « 1:02:03 ». On arrondit vers le haut pour ne jamais afficher 0:00 avant la fin.
    nonisolated static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Actions

    func setDuration(minutes: Int) {
        guard phase == .idle else { return }
        duration = TimeInterval(min(max(minutes, 1), 180) * 60)
        persist()
    }

    func start() {
        guard phase == .idle else { return }
        phase = .running(end: now().addingTimeInterval(duration))
        beginRunning()
    }

    func pause() {
        guard case .running(let end) = phase else { return }
        watchTask?.cancel()
        notifier.cancelTimerEnd()
        phase = .paused(remaining: max(0, end.timeIntervalSince(now())))
        persist()
    }

    func resume() {
        guard case .paused(let remaining) = phase else { return }
        phase = .running(end: now().addingTimeInterval(remaining))
        beginRunning()
    }

    func reset() {
        watchTask?.cancel()
        notifier.cancelTimerEnd()
        phase = .idle
        persist()
    }

    // MARK: - Interne

    private func beginRunning() {
        persist()

        // Surveillance : une seule attente, jusqu'à la date de fin exacte (pas de boucle de 1 s).
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while let self, case .running(let end) = self.phase {
                let wait = end.timeIntervalSince(self.now())
                if wait <= 0 {
                    self.finish()
                    return
                }
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
            }
        }

        // Notification locale : programmée par le système, donc livrée même si NookFlow
        // ne tourne plus au moment de la fin.
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.notifier.requestAuthorizationIfNeeded()
            self.notificationsDenied = !granted
            if granted, case .running(let end) = self.phase {
                self.notifier.scheduleTimerEnd(at: end)
            }
        }
    }

    private func finish() {
        guard case .running = phase else { return }
        phase = .finished
        persist()
        // Sans notification autorisée, on signale quand même la fin par un son.
        if notificationsDenied {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    // MARK: - Persistance (UserDefaults)

    private struct Snapshot: Codable {
        enum Kind: String, Codable { case idle, running, paused, finished }
        var duration: TimeInterval
        var kind: Kind
        var end: Date?
        var remaining: TimeInterval?
    }

    private func persist() {
        var snapshot = Snapshot(duration: duration, kind: .idle, end: nil, remaining: nil)
        switch phase {
        case .idle: break
        case .running(let end): snapshot.kind = .running; snapshot.end = end
        case .paused(let remaining): snapshot.kind = .paused; snapshot.remaining = remaining
        case .finished: snapshot.kind = .finished
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Relit l'état au lancement : un minuteur en cours reprend, ou est « terminé » si sa date est passée.
    private func restore() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }

        duration = snapshot.duration
        switch snapshot.kind {
        case .idle:
            phase = .idle
        case .paused:
            phase = .paused(remaining: snapshot.remaining ?? duration)
        case .finished:
            phase = .finished
        case .running:
            guard let end = snapshot.end else { phase = .idle; return }
            if end <= now() {
                phase = .finished
                persist()
            } else {
                phase = .running(end: end)
                beginRunning()
            }
        }
    }
}
