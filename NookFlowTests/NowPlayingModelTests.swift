import AppKit
import XCTest
@testable import NookFlow

@MainActor
final class FakeSpotify: SpotifyProviding {
    var isRunning = true
    var onPlaybackChange: ((PlaybackSnapshot) -> Void)?
    var onRunningChange: (() -> Void)?

    var snapshotResult: ScriptOutcome<PlaybackSnapshot?> = .success(nil)
    var artworkResult: ScriptOutcome<URL?> = .success(nil)
    var commandResult: ScriptOutcome<Void> = .success(())
    var shuffleResult: ScriptOutcome<Bool> = .success(false)

    private(set) var snapshotCalls = 0
    private(set) var commands: [SpotifyCommand] = []
    private(set) var shuffleToggles = 0

    func snapshot() -> ScriptOutcome<PlaybackSnapshot?> {
        snapshotCalls += 1
        return snapshotResult
    }

    func artworkURL() -> ScriptOutcome<URL?> { artworkResult }

    func perform(_ command: SpotifyCommand) -> ScriptOutcome<Void> {
        commands.append(command)
        return commandResult
    }

    func shuffleState() -> ScriptOutcome<Bool> { shuffleResult }

    func toggleShuffle() -> ScriptOutcome<Bool> {
        shuffleToggles += 1
        return shuffleResult
    }
}

@MainActor
final class NowPlayingModelTests: XCTestCase {
    private var spotify = FakeSpotify()
    private var clock = TestClock()
    private var defaults: UserDefaults!

    override func setUp() async throws {
        spotify = FakeSpotify()
        clock = TestClock()
        defaults = makeIsolatedDefaults(self)
    }

    private func makeModel(authorized: Bool = false, image: NSImage? = nil) -> NowPlayingModel {
        defaults.set(authorized, forKey: "music.automationGranted")
        let clock = self.clock
        return NowPlayingModel(
            service: spotify,
            defaults: defaults,
            now: { clock.date },
            loadImage: { _ in image }
        )
    }

    private func playing(_ title: String = "Titre", position: Double? = 0, duration: Double? = 200) -> PlaybackSnapshot {
        var info: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": title, "Artist": "Artiste", "Album": "Album"
        ]
        if let duration { info["Duration"] = duration * 1000 }
        if let position { info["Playback Position"] = position }
        return PlaybackSnapshot(userInfo: info)!
    }

    // MARK: - Annonces de Spotify (sans permission)

    func testPlaybackAnnouncementUpdatesTrackWithoutAnyAppleScript() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing("Ma vie"))

        XCTAssertEqual(model.track?.title, "Ma vie")
        XCTAssertEqual(model.track?.artist, "Artiste")
        XCTAssertEqual(model.playerState, .playing)
        XCTAssertEqual(spotify.snapshotCalls, 0)
    }

    func testStoppedAnnouncementClearsTrack() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing())
        spotify.onPlaybackChange?(PlaybackSnapshot(userInfo: ["Player State": "Stopped"])!)

        XCTAssertNil(model.track)
        XCTAssertEqual(model.playerState, .stopped)
    }

    func testPositionAdvancesWhilePlayingAndFreezesWhenPaused() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing(position: 10))
        clock.advance(5)
        XCTAssertEqual(model.position(at: clock.date) ?? -1, 15, accuracy: 0.001)

        spotify.onPlaybackChange?(PlaybackSnapshot(userInfo: [
            "Player State": "Paused", "Name": "Titre", "Artist": "Artiste", "Album": "Album",
            "Duration": 200_000.0, "Playback Position": 20.0
        ])!)
        clock.advance(100)
        XCTAssertEqual(model.position(at: clock.date) ?? -1, 20, accuracy: 0.001)
    }

    func testPositionNeverExceedsDuration() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing(position: 190, duration: 200))
        clock.advance(500)
        XCTAssertEqual(model.position(at: clock.date) ?? -1, 200, accuracy: 0.001)
    }

    // MARK: - Autorisation et requêtes

    func testNoRequestIsSentWithoutUserActionWhenNotAuthorized() {
        let model = makeModel(authorized: false)

        model.refresh(userInitiated: false)
        model.refreshIfNeeded()
        XCTAssertEqual(spotify.snapshotCalls, 0) // pas de fenêtre de permission par surprise

        model.refresh(userInitiated: true)
        XCTAssertEqual(spotify.snapshotCalls, 1)
    }

    func testAuthorizedModelAsksSpotifyOnlyWhenItKnowsNothing() {
        spotify.snapshotResult = .success(playing())
        let model = makeModel(authorized: true)

        model.refreshIfNeeded()
        model.refreshIfNeeded()
        model.refreshIfNeeded()

        XCTAssertEqual(spotify.snapshotCalls, 1) // ensuite, les annonces de Spotify suffisent
        XCTAssertNotNil(model.track)
    }

    func testRefusedPermissionDisablesCommands() {
        spotify.commandResult = .notAuthorized
        let model = makeModel()

        model.togglePlayPause()
        XCTAssertEqual(model.access, .denied)

        model.togglePlayPause()
        XCTAssertEqual(spotify.commands, [.playPause]) // la seconde commande n'est pas envoyée
    }

    func testSuccessfulCommandRemembersAuthorization() {
        let model = makeModel()
        model.next()

        XCTAssertEqual(model.access, .authorized)
        XCTAssertTrue(defaults.bool(forKey: "music.automationGranted"))
        XCTAssertEqual(spotify.commands, [.next])
    }

    func testSpotifyNotRunningSendsNothing() {
        spotify.isRunning = false
        let model = makeModel(authorized: true)

        model.togglePlayPause()

        XCTAssertTrue(spotify.commands.isEmpty)
        XCTAssertFalse(model.isSpotifyRunning)
    }

    // MARK: - Position et lecture aléatoire

    func testSeekSendsCommandAndMovesPositionImmediately() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing(position: 10, duration: 200))

        model.seek(to: 120)

        XCTAssertEqual(spotify.commands, [.seek(120)])
        XCTAssertEqual(model.position(at: clock.date) ?? -1, 120, accuracy: 0.001)
        clock.advance(3)
        XCTAssertEqual(model.position(at: clock.date) ?? -1, 123, accuracy: 0.001)
    }

    func testSeekIsClampedInsideTheTrack() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing(position: 10, duration: 200))

        model.seek(to: -50)
        model.seek(to: 9_999)

        XCTAssertEqual(spotify.commands, [.seek(0), .seek(199)])
    }

    func testSeekWorksEvenWhenCurrentPositionIsUnknown() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing(position: nil, duration: 200))
        XCTAssertFalse(model.hasPosition)

        model.seek(to: 50)

        XCTAssertEqual(spotify.commands, [.seek(50)])
        XCTAssertEqual(model.position(at: clock.date) ?? -1, 50, accuracy: 0.001)
    }

    func testSeekIgnoredWhenPermissionDenied() {
        spotify.commandResult = .notAuthorized
        let model = makeModel()
        spotify.onPlaybackChange?(playing(position: 10, duration: 200))

        model.seek(to: 100) // refusé : la position affichée ne change pas
        XCTAssertEqual(model.access, .denied)
        XCTAssertEqual(model.position(at: clock.date) ?? -1, 10, accuracy: 0.001)

        model.seek(to: 150)
        XCTAssertEqual(spotify.commands.count, 1)
    }

    func testToggleShuffleStoresNewState() {
        spotify.shuffleResult = .success(true)
        let model = makeModel()
        XCTAssertNil(model.isShuffling)

        model.toggleShuffle()

        XCTAssertEqual(model.isShuffling, true)
        XCTAssertEqual(spotify.shuffleToggles, 1)
        XCTAssertEqual(model.access, .authorized)
    }

    func testShuffleIsReadOnlyWhenAuthorized() {
        spotify.shuffleResult = .success(true)
        let unauthorized = makeModel(authorized: false)
        unauthorized.refreshIfNeeded()
        XCTAssertNil(unauthorized.isShuffling) // aucune requête sans autorisation

        let authorized = makeModel(authorized: true)
        authorized.refreshIfNeeded()
        XCTAssertEqual(authorized.isShuffling, true)
    }

    func testToggleShuffleRefusedDisablesAccess() {
        spotify.shuffleResult = .notAuthorized
        let model = makeModel()

        model.toggleShuffle()
        XCTAssertEqual(model.access, .denied)

        model.toggleShuffle()
        XCTAssertEqual(spotify.shuffleToggles, 1)
    }

    func testQuittingSpotifyForgetsShuffle() {
        spotify.shuffleResult = .success(true)
        let model = makeModel(authorized: true)
        model.refreshIfNeeded()
        XCTAssertEqual(model.isShuffling, true)

        spotify.isRunning = false
        spotify.onRunningChange?()

        XCTAssertNil(model.isShuffling)
    }

    func testQuittingSpotifyClearsEverything() {
        let model = makeModel()
        spotify.onPlaybackChange?(playing())
        spotify.isRunning = false
        spotify.onRunningChange?()

        XCTAssertFalse(model.isSpotifyRunning)
        XCTAssertNil(model.track)
        XCTAssertFalse(model.hasPosition)
    }

    // MARK: - Pochette

    func testArtworkIsLoadedOnlyAfterAuthorization() async throws {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        spotify.artworkResult = .success(URL(string: "https://i.scdn.co/image/test"))
        let model = makeModel(authorized: false, image: image)

        spotify.onPlaybackChange?(playing())
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(model.artwork) // pas d'autorisation : aucune requête, aucun téléchargement

        model.togglePlayPause() // première commande réussie = autorisation accordée
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotNil(model.artwork)
    }

    // MARK: - Analyse des données

    func testClockText() {
        XCTAssertEqual(NowPlayingModel.clockText(0), "0:00")
        XCTAssertEqual(NowPlayingModel.clockText(65.9), "1:05") // arrondi vers le bas
        XCTAssertEqual(NowPlayingModel.clockText(-3), "0:00")
    }

    func testParsingScriptOutput() {
        let output = ["playing", "Titre", "Artiste", "Album", "215000"].joined(separator: "\u{1F}")
        let snapshot = PlaybackSnapshot(scriptOutput: output)

        XCTAssertEqual(snapshot?.state, .playing)
        XCTAssertEqual(snapshot?.title, "Titre")
        XCTAssertEqual(snapshot?.artist, "Artiste")
        XCTAssertEqual(snapshot?.album, "Album")
        XCTAssertEqual(snapshot?.duration ?? 0, 215, accuracy: 0.001)
        XCTAssertNil(snapshot?.position)
    }

    func testParsingStoppedScriptOutput() {
        let snapshot = PlaybackSnapshot(scriptOutput: "stopped")
        XCTAssertEqual(snapshot?.state, .stopped)
        XCTAssertNil(snapshot?.title)
    }

    func testParsingEmptyScriptOutputFails() {
        XCTAssertNil(PlaybackSnapshot(scriptOutput: ""))
    }

    func testParsingNotificationUserInfo() {
        let snapshot = PlaybackSnapshot(userInfo: [
            "Player State": "Paused", "Name": "X", "Artist": "Y", "Album": "Z",
            "Duration": 180_000, "Playback Position": 12.5
        ])
        XCTAssertEqual(snapshot?.state, .paused)
        XCTAssertEqual(snapshot?.duration ?? 0, 180, accuracy: 0.001)
        XCTAssertEqual(snapshot?.position ?? 0, 12.5, accuracy: 0.001)
    }

    func testNotificationWithoutPlayerStateIsIgnored() {
        XCTAssertNil(PlaybackSnapshot(userInfo: ["Name": "X"]))
    }
}
