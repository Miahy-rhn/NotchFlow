import XCTest
@testable import NookFlow

@MainActor
final class NotchStateTests: XCTestCase {
    private func makeState() -> (NotchState, AppPreferences) {
        let preferences = AppPreferences(defaults: makeIsolatedDefaults(self))
        return (NotchState(preferences: preferences), preferences)
    }

    func testResolvedFallsBackToFirstEnabledWidget() {
        let (_, preferences) = makeState()
        preferences.setEnabled(false, for: .files)

        XCTAssertEqual(preferences.resolved(.files), preferences.visibleWidgets.first)
        XCTAssertEqual(preferences.resolved(.timer), .timer) // activé : inchangé
    }

    func testResolvedFollowsCustomOrder() {
        let (_, preferences) = makeState()
        preferences.move(.music, by: -4) // Musique passe en première position
        preferences.setEnabled(false, for: .notes)

        XCTAssertEqual(preferences.visibleWidgets.first, .music)
        XCTAssertEqual(preferences.resolved(.notes), .music)
    }

    func testResolveSelectionMovesAwayFromDisabledWidget() {
        let (state, preferences) = makeState()
        state.selectedWidget = .calendar
        preferences.setEnabled(false, for: .calendar)

        state.resolveSelection()

        XCTAssertNotEqual(state.selectedWidget, .calendar)
        XCTAssertTrue(preferences.isEnabled(state.selectedWidget))
    }

    func testResolveSelectionKeepsEnabledWidget() {
        let (state, _) = makeState()
        state.selectedWidget = .timer
        state.resolveSelection()
        XCTAssertEqual(state.selectedWidget, .timer)
    }

    func testResetAfterCloseOnlyWhenPreferenceIsOn() {
        let (state, preferences) = makeState()
        state.selectedWidget = .music

        state.resetSelectionAfterClose()
        XCTAssertEqual(state.selectedWidget, .music) // préférence désactivée par défaut

        preferences.openOnFirstWidget = true
        state.resetSelectionAfterClose()
        XCTAssertEqual(state.selectedWidget, preferences.visibleWidgets.first)
    }
}
