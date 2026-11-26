import SwiftUI
import AppKit

struct MusicWidgetView: View {
    let model: NowPlayingModel

    var body: some View {
        Group {
            if !model.isSpotifyRunning {
                notRunningView
            } else if let track = model.track {
                playerView(track)
            } else {
                noInfoView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refreshIfNeeded() }
    }

    // MARK: - Lecteur

    private func playerView(_ track: NowPlayingModel.Track) -> some View {
        HStack(spacing: 16) {
            artworkView

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                if let duration = track.duration { progressView(duration: duration) }

                controls
                footnote
            }
        }
    }

    private var artworkView: some View {
        Group {
            if let image = model.artwork {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    /// Ne se rafraîchit chaque seconde que pendant la lecture, panneau ouvert, onglet visible.
    @ViewBuilder
    private func progressView(duration: TimeInterval) -> some View {
        if model.playerState == .playing {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                seekBar(position: model.position(at: context.date), duration: duration)
            }
        } else {
            seekBar(position: model.position(at: .now), duration: duration)
        }
    }

    private func seekBar(position: TimeInterval?, duration: TimeInterval) -> some View {
        SeekBar(
            position: position,
            duration: duration,
            isEnabled: model.access != .denied,
            onSeek: { model.seek(to: $0) }
        )
    }

    private var controls: some View {
        let isDenied = model.access == .denied
        return HStack(spacing: 18) {
            // Lecture aléatoire (le « mix » de Spotify). Allumé = blanc plein.
            Button { model.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.isShuffling == true ? Color.green : Color.white.opacity(0.6))
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isShuffling == true ? "Lecture aléatoire activée" : "Activer la lecture aléatoire")
            .accessibilityLabel("Lecture aléatoire")
            .accessibilityValue(model.isShuffling == true ? "activée" : "désactivée")

            controlButton("backward.fill", label: "Morceau précédent", size: 15) { model.previous() }

            Button { model.togglePlayPause() } label: {
                Image(systemName: model.playerState == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.playerState == .playing ? "Pause" : "Lecture")

            controlButton("forward.fill", label: "Morceau suivant", size: 15) { model.next() }

            // Un Jam ne peut pas être démarré par une app tierce (Spotify n'offre aucune commande
            // pour cela) : ce bouton ouvre simplement Spotify, où se trouve l'option « Jam ».
            Button { activateSpotify() } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir Spotify (pour lancer un Jam : menu des appareils de lecture)")
            .accessibilityLabel("Ouvrir Spotify")
        }
        .disabled(isDenied)
        .opacity(isDenied ? 0.35 : 1)
    }

    private func controlButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var footnote: some View {
        if model.access == .denied {
            HStack(spacing: 8) {
                Text("Contrôle de Spotify refusé.")
                    .foregroundStyle(.orange)
                Button("Réglages") { openAutomationSettings() }
                    .buttonStyle(NookPillStyle(prominent: false, compact: true))
                Button("Réessayer") { model.refresh(userInitiated: true) }
                    .buttonStyle(NookPillStyle(prominent: false, compact: true))
            }
            .font(.caption2)
        } else if model.access == .unknown {
            Text("Le premier clic demande l'autorisation de contrôler Spotify, ainsi que d'afficher la pochette.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        } else if let message = model.message {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    // MARK: - États sans morceau

    private var notRunningView: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.title2)
            Text("Spotify n'est pas ouvert")
                .font(.caption)
            Button("Ouvrir Spotify") { openSpotify() }
                .buttonStyle(NookPillStyle(prominent: true, compact: true))
        }
        .foregroundStyle(.white.opacity(0.65))
    }

    @ViewBuilder
    private var noInfoView: some View {
        switch model.access {
        case .unknown:
            infoMessage(
                "NookFlow reçoit les infos de Spotify à chaque changement de morceau. Lance un morceau, ou autorise NookFlow à lire l'état actuel de Spotify.",
                buttons: [("Autoriser Spotify", true, { model.refresh(userInitiated: true) })]
            )
        case .denied:
            infoMessage(
                "Le contrôle de Spotify est refusé. Autorise NookFlow dans Réglages Système > Confidentialité et sécurité > Automatisation.",
                buttons: [
                    ("Ouvrir les Réglages", true, { openAutomationSettings() }),
                    ("Réessayer", false, { model.refresh(userInitiated: true) })
                ]
            )
        case .authorized:
            infoMessage("Aucun morceau en cours. Lance une lecture dans Spotify.", buttons: [])
        }
    }

    private func infoMessage(_ text: String, buttons: [(String, Bool, () -> Void)]) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            HStack(spacing: 8) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    Button(button.0, action: button.2)
                        .buttonStyle(NookPillStyle(prominent: button.1, compact: true))
                }
            }
        }
    }

    // MARK: - Ouvertures

    private func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyBridge.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func activateSpotify() {
        NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyBridge.bundleIdentifier)
            .first?.activate()
    }

    private func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Barre de position

/// Barre cliquable et déplaçable pour se positionner dans le morceau.
/// Pendant le glissement, la barre suit le doigt ; Spotify n'est contacté qu'au relâchement.
private struct SeekBar: View {
    /// nil : position inconnue (Spotify ne l'a pas encore annoncée). La barre reste utilisable.
    let position: TimeInterval?
    let duration: TimeInterval
    let isEnabled: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?

    private var currentFraction: Double {
        guard duration > 0, let position else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var body: some View {
        let fraction = dragFraction ?? currentFraction
        let shown = fraction * duration
        let hasShownTime = position != nil || dragFraction != nil

        HStack(spacing: 6) {
            Text(hasShownTime ? NowPlayingModel.clockText(shown) : "–:––")
                .frame(minWidth: 30, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: geometry.size.width * fraction)
                    Circle()
                        .fill(.white)
                        .frame(width: dragFraction == nil ? 0 : 10, height: 10)
                        .offset(x: max(0, geometry.size.width * fraction - 5))
                }
                .frame(height: dragFraction == nil ? 4 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            dragFraction = Self.fraction(value.location.x, width: geometry.size.width)
                        }
                        .onEnded { value in
                            guard isEnabled else { dragFraction = nil; return }
                            let target = Self.fraction(value.location.x, width: geometry.size.width) * duration
                            dragFraction = nil
                            onSeek(target)
                        }
                )
            }
            .frame(height: 18)

            Text(NowPlayingModel.clockText(duration))
                .frame(minWidth: 30, alignment: .leading)
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position dans le morceau")
        .accessibilityValue(position.map { "\(NowPlayingModel.clockText($0)) sur \(NowPlayingModel.clockText(duration))" } ?? "position inconnue")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onSeek((position ?? 0) + 5)
            case .decrement: onSeek((position ?? 0) - 5)
            @unknown default: break
            }
        }
    }

    private static func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }
}

// MARK: - Fond de l'onglet Musique

/// Pochette agrandie et floutée, assombrie pour garder le texte lisible.
/// Reste noir sur la hauteur de l'encoche pour s'y fondre.
struct MusicBackdrop: View {
    let image: NSImage
    let notchHeight: CGFloat

    var body: some View {
        Color.clear
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.6)
                    .saturation(1.25)
                    .blur(radius: 45)
            }
            .overlay(Color.black.opacity(0.5))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: notchHeight + 30)
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
