import AppKit
import Foundation
import Observation

/// État du lecteur Spotify et actions de l'utilisateur.
/// Tout vient d'événements (notifications de Spotify, clics) : aucune boucle de mise à jour.
@MainActor
@Observable
final class NowPlayingModel {
    enum PlayerState: Equatable {
        case stopped, paused, playing
    }

    /// Autorisation « Automatisation » (nécessaire pour les commandes et la pochette).
    enum Access: Equatable {
        case unknown     // jamais demandée ou jamais confirmée
        case authorized
        case denied
    }

    struct Track: Equatable {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval?
    }

    private(set) var track: Track?
    private(set) var playerState: PlayerState = .stopped
    private(set) var artwork: NSImage?
    private(set) var access: Access
    private(set) var isSpotifyRunning: Bool
    /// Lecture aléatoire : nil tant qu'on ne la connaît pas.
    private(set) var isShuffling: Bool?
    /// Message d'erreur compréhensible, affiché dans le widget.
    private(set) var message: String?

    @ObservationIgnored private let service: SpotifyProviding
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let loadImage: (URL) async -> NSImage?
    private var anchor: (position: TimeInterval, at: Date)?
    @ObservationIgnored private var lastEventAt = Date.distantPast
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private static let grantedKey = "music.automationGranted"

    init(
        service: SpotifyProviding,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        loadImage: @escaping (URL) async -> NSImage? = NowPlayingModel.downloadImage
    ) {
        self.service = service
        self.defaults = defaults
        self.now = now
        self.loadImage = loadImage
        self.access = defaults.bool(forKey: Self.grantedKey) ? .authorized : .unknown
        self.isSpotifyRunning = service.isRunning

        service.onPlaybackChange = { [weak self] snapshot in self?.apply(snapshot) }
        service.onRunningChange = { [weak self] in self?.runningChanged() }
    }

    // MARK: - Lecture

    /// Position estimée à `date` : dernière position connue + temps écoulé si la lecture est en cours.
    func position(at date: Date) -> TimeInterval? {
        guard let anchor else { return nil }
        var value = anchor.position
        if playerState == .playing { value += date.timeIntervalSince(anchor.at) }
        if let duration = track?.duration { value = min(value, duration) }
        return max(0, value)
    }

    /// « 3:07 » (arrondi vers le bas : un temps écoulé ne dépasse jamais la réalité).
    nonisolated static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Vrai quand la position de lecture est connue (elle vient des annonces de Spotify).
    var hasPosition: Bool { anchor != nil }

    // MARK: - Actions

    /// Relit Spotify seulement si on ne sait encore rien : ensuite, ses annonces suffisent.
    /// Cela évite de lui envoyer des requêtes AppleScript à chaque ouverture du panneau.
    func refreshIfNeeded() {
        isSpotifyRunning = service.isRunning
        if isSpotifyRunning, track == nil { refresh(userInitiated: false) }
        refreshShuffle()
    }

    /// L'état « aléatoire » ne figure pas dans les annonces de Spotify (l'utilisateur peut aussi
    /// le changer dans Spotify) : on le relit à l'ouverture de l'onglet, une simple propriété.
    private func refreshShuffle() {
        guard isSpotifyRunning, access == .authorized else { return }
        if case .success(let value) = service.shuffleState() { isShuffling = value }
    }

    /// Relit l'état de Spotify. Sans autorisation connue, ne contacte Spotify que si
    /// `userInitiated` (clic sur « Autoriser »), pour ne jamais déclencher la fenêtre de
    /// permission par surprise.
    func refresh(userInitiated: Bool) {
        isSpotifyRunning = service.isRunning
        guard isSpotifyRunning else {
            clearPlayback()
            return
        }
        guard access == .authorized || userInitiated else { return }

        switch service.snapshot() {
        case .success(let snapshot):
            markAuthorized()
            if let snapshot { apply(snapshot) } else { clearPlayback() }
        case .notAuthorized:
            markDenied()
        case .notRunning:
            isSpotifyRunning = false
            clearPlayback()
        case .failed(let reason):
            message = "Lecture impossible : \(reason)"
        }
    }

    func togglePlayPause() { send(.playPause) }
    func next() { send(.next) }
    func previous() { send(.previous) }

    /// Se place à `seconds` dans le morceau (borné entre 0 et la fin).
    /// La position affichée suit tout de suite ; Spotify confirme ensuite par son annonce.
    func seek(to seconds: TimeInterval) {
        // Écrire une position fonctionne même si on ignore la position actuelle.
        guard let duration = track?.duration else { return }
        let target = min(max(0, seconds), max(0, duration - 1))
        if execute(.seek(target)) { anchor = (target, now()) }
    }

    func toggleShuffle() {
        guard access != .denied else { return }
        isSpotifyRunning = service.isRunning
        guard isSpotifyRunning else { return }
        switch service.toggleShuffle() {
        case .success(let value):
            markAuthorized()
            isShuffling = value
        case .notAuthorized: markDenied()
        case .notRunning:
            isSpotifyRunning = false
            clearPlayback()
        case .failed(let reason): message = "Commande impossible : \(reason)"
        }
    }

    // MARK: - Interne

    private func send(_ command: SpotifyCommand) {
        guard execute(command) else { return }
        // Spotify annonce le changement lui-même ; ce second contrôle couvre le cas
        // où la notification n'arriverait pas.
        let sentAt = now()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.lastEventAt < sentAt else { return } // Spotify a déjà annoncé le changement
            self.refresh(userInitiated: false)
        }
    }

    /// Envoie la commande et gère les erreurs communes. Renvoie vrai si Spotify l'a exécutée.
    private func execute(_ command: SpotifyCommand) -> Bool {
        guard access != .denied else { return false } // les boutons sont désactivés dans ce cas
        isSpotifyRunning = service.isRunning
        guard isSpotifyRunning else { return false }

        switch service.perform(command) {
        case .success:
            markAuthorized()
            return true
        case .notAuthorized:
            markDenied()
        case .notRunning:
            isSpotifyRunning = false
            clearPlayback()
        case .failed(let reason):
            message = "Commande impossible : \(reason)"
        }
        return false
    }

    private func runningChanged() {
        isSpotifyRunning = service.isRunning
        if !isSpotifyRunning { clearPlayback() }
    }

    private func apply(_ snapshot: PlaybackSnapshot) {
        let previousTrack = track
        lastEventAt = now()
        isSpotifyRunning = true
        switch snapshot.state {
        case .playing: playerState = .playing
        case .paused: playerState = .paused
        case .stopped: playerState = .stopped
        }

        if let title = snapshot.title, !title.isEmpty {
            track = Track(
                title: title,
                artist: snapshot.artist ?? "",
                album: snapshot.album ?? "",
                duration: snapshot.duration
            )
        } else if snapshot.state == .stopped {
            track = nil
        }

        if let position = snapshot.position {
            anchor = (position, now())
        } else if track != previousTrack {
            anchor = nil // nouvelle piste sans position connue : on attend l'annonce de Spotify
        }

        if track != previousTrack {
            artwork = nil
            artworkTask?.cancel()
            fetchArtwork()
        }
    }

    private func clearPlayback() {
        track = nil
        playerState = .stopped
        artwork = nil
        anchor = nil
        isShuffling = nil
        artworkTask?.cancel()
    }

    private func markAuthorized() {
        let wasAuthorized = (access == .authorized)
        access = .authorized
        message = nil
        defaults.set(true, forKey: Self.grantedKey)
        // Première autorisation : le morceau en cours est déjà affiché, il lui manque la pochette.
        if !wasAuthorized, artwork == nil { fetchArtwork() }
    }

    private func markDenied() {
        access = .denied
        defaults.set(false, forKey: Self.grantedKey)
    }

    /// La pochette est une image publique de Spotify. On ne la télécharge qu'avec l'autorisation
    /// d'automatisation, et rien n'est envoyé d'autre que la requête d'image elle-même.
    private func fetchArtwork() {
        guard access == .authorized, let expected = track else { return }

        switch service.artworkURL() {
        case .success(let url):
            guard let url else { return }
            artworkTask = Task { [weak self] in
                guard let self else { return }
                let image = await self.loadImage(url)
                guard !Task.isCancelled, self.track == expected else { return }
                self.artwork = image
            }
        case .notAuthorized:
            markDenied()
        case .notRunning, .failed:
            break // pas de pochette : le widget affiche un visuel de remplacement
        }
    }

    nonisolated static func downloadImage(_ url: URL) async -> NSImage? {
        guard url.scheme == "https" else { return nil }
        let session = URLSession(configuration: .ephemeral) // aucun cookie, aucun cache disque
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}
