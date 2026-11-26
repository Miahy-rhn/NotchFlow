import AppKit
import Foundation

/// Résultat d'une commande envoyée à Spotify.
enum ScriptOutcome<Value> {
    case success(Value)
    case notRunning
    /// L'utilisateur a refusé (ou n'a pas encore accordé) l'autorisation « Automatisation ».
    case notAuthorized
    case failed(String)
}

enum SpotifyCommand: Equatable {
    case playPause
    case next
    case previous
    /// Se place à cet instant du morceau (en secondes).
    case seek(TimeInterval)
}

/// Photo de l'état de lecture, issue d'une notification ou d'une lecture AppleScript.
struct PlaybackSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case stopped, paused, playing
    }

    var state: State
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval?
    var position: TimeInterval?

    /// Notification `com.spotify.client.PlaybackStateChanged`.
    /// Clés publiées par Spotify : "Player State", "Name", "Artist", "Album", "Duration" (ms),
    /// "Playback Position" (secondes).
    init?(userInfo: [AnyHashable: Any]) {
        guard let rawState = userInfo["Player State"] as? String else { return nil }
        self.state = Self.parseState(rawState)
        self.title = userInfo["Name"] as? String
        self.artist = userInfo["Artist"] as? String
        self.album = userInfo["Album"] as? String
        if let ms = (userInfo["Duration"] as? NSNumber)?.doubleValue, ms > 0 { duration = ms / 1000 }
        self.position = (userInfo["Playback Position"] as? NSNumber)?.doubleValue
    }

    /// Sortie du script AppleScript de lecture (champs séparés par le caractère 31).
    init?(scriptOutput: String) {
        let parts = scriptOutput.components(separatedBy: "\u{1F}")
        guard let first = parts.first, !first.isEmpty else { return nil }
        self.state = Self.parseState(first)
        guard parts.count >= 5 else { return }
        self.title = parts[1]
        self.artist = parts[2]
        self.album = parts[3]
        if let ms = Self.number(parts[4]), ms > 0 { duration = ms / 1000 }
    }

    private static func parseState(_ raw: String) -> State {
        switch raw.lowercased() {
        case "playing": .playing
        case "paused": .paused
        default: .stopped
        }
    }

    /// AppleScript peut écrire les décimaux avec une virgule selon la région du Mac.
    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
}

/// Ce dont le widget a besoin pour parler à Spotify. Un protocole simple permet de le
/// remplacer par un faux lecteur dans les tests.
@MainActor
protocol SpotifyProviding: AnyObject {
    var isRunning: Bool { get }
    /// Spotify annonce lui-même chaque changement de morceau ou d'état (sans permission, sans polling).
    var onPlaybackChange: ((PlaybackSnapshot) -> Void)? { get set }
    /// Spotify vient d'être lancé ou fermé.
    var onRunningChange: (() -> Void)? { get set }

    func snapshot() -> ScriptOutcome<PlaybackSnapshot?>
    func artworkURL() -> ScriptOutcome<URL?>
    func perform(_ command: SpotifyCommand) -> ScriptOutcome<Void>
    /// Lecture aléatoire activée ou non.
    func shuffleState() -> ScriptOutcome<Bool>
    /// Inverse la lecture aléatoire et renvoie le nouvel état.
    func toggleShuffle() -> ScriptOutcome<Bool>
}

/// Pont vers Spotify :
/// - notifications distribuées pour être informé sans rien demander à personne ;
/// - AppleScript (API publique) pour les commandes, la lecture initiale et la pochette.
///
/// Règle d'or : on ne parle jamais à Spotify s'il n'est pas déjà ouvert, car un `tell application`
/// le lancerait tout seul.
@MainActor
final class SpotifyBridge: SpotifyProviding {
    nonisolated static let bundleIdentifier = "com.spotify.client"

    var onPlaybackChange: ((PlaybackSnapshot) -> Void)?
    var onRunningChange: (() -> Void)?

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = [] // vivent autant que l'app

    init() {
        let distributed = DistributedNotificationCenter.default()
        let playback = distributed.addObserver(
            forName: NSNotification.Name("\(Self.bundleIdentifier).PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let snapshot = PlaybackSnapshot(userInfo: info) else { return }
            Task { @MainActor in self?.onPlaybackChange?(snapshot) }
        }
        observers.append((distributed, playback))

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleIdentifier else { return }
                Task { @MainActor in self?.onRunningChange?() }
            }
            observers.append((workspace, token))
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    // MARK: - Lecture

    func snapshot() -> ScriptOutcome<PlaybackSnapshot?> {
        let script = """
        tell application id "\(Self.bundleIdentifier)"
            set fieldSeparator to character id 31
            set stateText to (player state) as string
            if stateText is "stopped" then return stateText
            set currentTrackRef to current track
            set titleText to name of currentTrackRef
            set artistText to artist of currentTrackRef
            set albumText to album of currentTrackRef
            set durationText to (duration of currentTrackRef) as string
            return stateText & fieldSeparator & titleText & fieldSeparator & artistText & fieldSeparator & albumText & fieldSeparator & durationText
        end tell
        """
        switch run(script) {
        case .success(let output): return .success(PlaybackSnapshot(scriptOutput: output))
        case .notRunning: return .notRunning
        case .notAuthorized: return .notAuthorized
        case .failed(let message): return .failed(message)
        }
    }

    /// URL de la pochette (image hébergée par Spotify). Elle n'est téléchargée que si l'utilisateur
    /// a déjà autorisé le contrôle de Spotify.
    func artworkURL() -> ScriptOutcome<URL?> {
        let script = """
        tell application id "\(Self.bundleIdentifier)"
            return artwork url of current track
        end tell
        """
        switch run(script) {
        case .success(let output): return .success(URL(string: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        case .notRunning: return .notRunning
        case .notAuthorized: return .notAuthorized
        case .failed(let message): return .failed(message)
        }
    }

    // MARK: - Commandes

    func perform(_ command: SpotifyCommand) -> ScriptOutcome<Void> {
        let statement: String
        switch command {
        case .playPause: statement = "playpause"
        case .next: statement = "next track"
        case .previous: statement = "previous track"
        // Entier : évite tout souci de virgule décimale selon la région du Mac.
        // On ÉCRIT la position, on ne la lit jamais (lire `player position` perturbait Spotify).
        case .seek(let seconds): statement = "set player position to \(Int(max(0, seconds).rounded(.down)))"
        }
        switch run("tell application id \"\(Self.bundleIdentifier)\" to \(statement)") {
        case .success: return .success(())
        case .notRunning: return .notRunning
        case .notAuthorized: return .notAuthorized
        case .failed(let message): return .failed(message)
        }
    }

    // MARK: - Lecture aléatoire

    func shuffleState() -> ScriptOutcome<Bool> {
        let script = """
        tell application id "\(Self.bundleIdentifier)"
            return (shuffling as string)
        end tell
        """
        return boolOutcome(run(script))
    }

    func toggleShuffle() -> ScriptOutcome<Bool> {
        let script = """
        tell application id "\(Self.bundleIdentifier)"
            set wasShuffling to shuffling
            set shuffling to (not wasShuffling)
            return ((not wasShuffling) as string)
        end tell
        """
        return boolOutcome(run(script))
    }

    private func boolOutcome(_ outcome: ScriptOutcome<String>) -> ScriptOutcome<Bool> {
        switch outcome {
        case .success(let output): return .success(output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true")
        case .notRunning: return .notRunning
        case .notAuthorized: return .notAuthorized
        case .failed(let message): return .failed(message)
        }
    }

    // MARK: - Exécution AppleScript

    private func run(_ source: String) -> ScriptOutcome<String> {
        guard isRunning else { return .notRunning }
        guard let script = NSAppleScript(source: source) else { return .failed("Script invalide") }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let number = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "erreur inconnue"
            switch number {
            case -1743: return .notAuthorized   // autorisation « Automatisation » refusée
            case -600: return .notRunning       // Spotify s'est fermé entre-temps
            default: return .failed(message)
            }
        }
        return .success(result.stringValue ?? "")
    }
}
