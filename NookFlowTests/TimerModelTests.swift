import XCTest
@testable import NookFlow

/// Horloge contrôlée : les tests décident du temps qui passe.
final class TestClock {
    var date: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_000_000)) { self.date = date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
final class FakeNotifier: TimerNotifying {
    var granted = true
    private(set) var scheduled: [Date] = []
    private(set) var cancelCount = 0

    func requestAuthorizationIfNeeded() async -> Bool { granted }
    func scheduleTimerEnd(at date: Date) { scheduled.append(date) }
    func cancelTimerEnd() { cancelCount += 1 }
}

/// UserDefaults jetable, pour ne jamais toucher aux vrais réglages.
@MainActor
func makeIsolatedDefaults(_ testCase: XCTestCase) -> UserDefaults {
    let name = "nookflow.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    testCase.addTeardownBlock { defaults.removePersistentDomain(forName: name) }
    return defaults
}

@MainActor
final class TimerModelTests: XCTestCase {
    private var clock = TestClock()
    private var notifier = FakeNotifier()
    private var defaults: UserDefaults!

    override func setUp() async throws {
        clock = TestClock()
        notifier = FakeNotifier()
        defaults = makeIsolatedDefaults(self)
    }

    private func makeModel() -> TimerModel {
        let clock = self.clock
        return TimerModel(notifier: notifier, defaults: defaults, now: { clock.date })
    }

    // MARK: - Démarrage et temps restant

    func testStartSetsEndDateFromDuration() {
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.phase, .running(end: clock.date.addingTimeInterval(300)))
    }

    func testRemainingIsEndMinusNowEvenWithoutAnyTick() {
        let model = makeModel()
        model.start()
        clock.advance(120) // aucune mise à jour visuelle n'a eu lieu entre-temps
        XCTAssertEqual(model.remaining(at: clock.date), 180, accuracy: 0.001)
    }

    func testRemainingNeverNegative() {
        let model = makeModel()
        model.start()
        clock.advance(10_000)
        XCTAssertEqual(model.remaining(at: clock.date), 0)
    }

    // MARK: - Pause, reprise, réinitialisation

    func testPauseKeepsRemainingAndResumeUsesIt() {
        let model = makeModel()
        model.start()
        clock.advance(100)
        model.pause()
        XCTAssertEqual(model.phase, .paused(remaining: 200))

        clock.advance(1_000) // le temps passe pendant la pause
        XCTAssertEqual(model.remaining(at: clock.date), 200)

        model.resume()
        XCTAssertEqual(model.phase, .running(end: clock.date.addingTimeInterval(200)))
    }

    func testResetReturnsToIdleWithChosenDuration() {
        let model = makeModel()
        model.setDuration(minutes: 10)
        model.start()
        model.reset()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.remaining(at: clock.date), 600)
    }

    func testStartIsIgnoredWhenAlreadyRunning() {
        let model = makeModel()
        model.start()
        let first = model.phase
        clock.advance(50)
        model.start()
        XCTAssertEqual(model.phase, first)
    }

    // MARK: - Durée

    func testDurationIsClamped() {
        let model = makeModel()
        model.setDuration(minutes: 0)
        XCTAssertEqual(model.duration, 60)
        model.setDuration(minutes: 999)
        XCTAssertEqual(model.duration, 180 * 60)
    }

    func testDurationCannotChangeWhileRunning() {
        let model = makeModel()
        model.start()
        model.setDuration(minutes: 25)
        XCTAssertEqual(model.duration, 300)
    }

    // MARK: - Persistance

    func testRunningTimerSurvivesRelaunch() {
        let first = makeModel()
        first.start()
        let expected = first.phase
        clock.advance(100)

        let second = makeModel()
        XCTAssertEqual(second.phase, expected)
    }

    func testTimerFinishedWhileAppWasClosed() {
        let first = makeModel()
        first.start()
        clock.advance(400) // la date de fin est dépassée

        let second = makeModel()
        XCTAssertEqual(second.phase, .finished)
    }

    func testPausedTimerSurvivesRelaunch() {
        let first = makeModel()
        first.start()
        clock.advance(60)
        first.pause()

        let second = makeModel()
        XCTAssertEqual(second.phase, .paused(remaining: 240))
    }

    // MARK: - Notifications

    func testStartSchedulesNotificationAtEndDate() async throws {
        let model = makeModel()
        model.start()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(notifier.scheduled, [clock.date.addingTimeInterval(300)])
        model.reset()
    }

    func testPauseCancelsNotification() async throws {
        let model = makeModel()
        model.start()
        try await Task.sleep(for: .milliseconds(150))
        let before = notifier.cancelCount
        model.pause()
        XCTAssertGreaterThan(notifier.cancelCount, before)
    }

    func testDeniedNotificationsAreReportedAndNothingIsScheduled() async throws {
        notifier.granted = false
        let model = makeModel()
        model.start()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(model.notificationsDenied)
        XCTAssertTrue(notifier.scheduled.isEmpty)
        model.reset()
    }

    // MARK: - Affichage

    func testFormat() {
        XCTAssertEqual(TimerModel.format(0), "0:00")
        XCTAssertEqual(TimerModel.format(59.2), "1:00") // arrondi vers le haut
        XCTAssertEqual(TimerModel.format(125), "2:05")
        XCTAssertEqual(TimerModel.format(3661), "1:01:01")
        XCTAssertEqual(TimerModel.format(-5), "0:00")
    }
}
