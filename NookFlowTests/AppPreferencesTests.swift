import XCTest
@testable import NookFlow

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = makeIsolatedDefaults(self)
    }

    private func makePreferences() -> AppPreferences {
        AppPreferences(defaults: defaults)
    }

    func testDefaultValues() {
        let prefs = makePreferences()
        XCTAssertEqual(prefs.visibleWidgets, WidgetID.allCases)
        XCTAssertEqual(prefs.openTrigger, .hoverOrClick)
        XCTAssertTrue(prefs.autoClose)
        XCTAssertFalse(prefs.openOnFirstWidget)
        XCTAssertEqual(prefs.theme, .black)
        XCTAssertEqual(prefs.animationStyle, .smooth)
        XCTAssertEqual(prefs.hoverOpenDelay, AppPreferences.defaultHoverOpenDelay)
        XCTAssertEqual(prefs.closeDelay, AppPreferences.defaultCloseDelay)
    }

    // MARK: - Widgets

    func testDisablingHidesWidgetButKeepsOrder() {
        let prefs = makePreferences()
        prefs.setEnabled(false, for: .calendar)

        XCTAssertFalse(prefs.isEnabled(.calendar))
        XCTAssertFalse(prefs.visibleWidgets.contains(.calendar))
        XCTAssertTrue(prefs.widgetOrder.contains(.calendar))
    }

    func testLastEnabledWidgetCannotBeDisabled() {
        let prefs = makePreferences()
        for widget in WidgetID.allCases { prefs.setEnabled(false, for: widget) }

        XCTAssertEqual(prefs.visibleWidgets.count, 1)
        let last = prefs.visibleWidgets[0]
        XCTAssertFalse(prefs.canDisable(last))
    }

    func testReenablingWorks() {
        let prefs = makePreferences()
        prefs.setEnabled(false, for: .music)
        prefs.setEnabled(true, for: .music)
        XCTAssertTrue(prefs.isEnabled(.music))
    }

    func testMoveChangesPriority() {
        let prefs = makePreferences()
        XCTAssertNotEqual(prefs.visibleWidgets.first, .music)

        for _ in 0..<4 { prefs.move(.music, by: -1) }
        XCTAssertEqual(prefs.visibleWidgets.first, .music)
    }

    func testMoveBeyondEdgesIsIgnored() {
        let prefs = makePreferences()
        let before = prefs.widgetOrder
        prefs.move(before[0], by: -1)
        prefs.move(before[before.count - 1], by: 1)
        XCTAssertEqual(prefs.widgetOrder, before)
    }

    // MARK: - Persistance

    func testSettingsSurviveRestart() {
        let prefs = makePreferences()
        prefs.theme = .midnight
        prefs.hoverOpenDelay = 0.4
        prefs.autoClose = false
        prefs.openTrigger = .clickOnly
        prefs.animationStyle = .snappy
        prefs.setEnabled(false, for: .files)
        prefs.move(.timer, by: -1)

        let reloaded = makePreferences()
        XCTAssertEqual(reloaded.theme, .midnight)
        XCTAssertEqual(reloaded.hoverOpenDelay, 0.4)
        XCTAssertFalse(reloaded.autoClose)
        XCTAssertEqual(reloaded.openTrigger, .clickOnly)
        XCTAssertEqual(reloaded.animationStyle, .snappy)
        XCTAssertFalse(reloaded.isEnabled(.files))
        XCTAssertEqual(reloaded.widgetOrder, prefs.widgetOrder)
    }

    func testResetRestoresDefaultsAndPersistsThem() {
        let prefs = makePreferences()
        prefs.theme = .plum
        prefs.autoClose = false
        prefs.setEnabled(false, for: .notes)

        prefs.resetToDefaults()

        let reloaded = makePreferences()
        XCTAssertEqual(reloaded.theme, .black)
        XCTAssertTrue(reloaded.autoClose)
        XCTAssertEqual(reloaded.visibleWidgets, WidgetID.allCases)
    }

    func testOnChangeIsCalledOnModification() {
        let prefs = makePreferences()
        var calls = 0
        prefs.onChange = { calls += 1 }

        prefs.theme = .forest
        XCTAssertGreaterThanOrEqual(calls, 1)
    }

    // MARK: - Données anciennes ou invalides

    func testWidgetsAddedByAnUpdateAreAppended() {
        defaults.set(["notes", "files"], forKey: "prefs.widgetOrder") // ancienne version : 2 widgets seulement
        let prefs = makePreferences()

        XCTAssertEqual(Array(prefs.widgetOrder.prefix(2)), [.notes, .files])
        XCTAssertEqual(Set(prefs.widgetOrder), Set(WidgetID.allCases))
        XCTAssertEqual(prefs.widgetOrder.count, WidgetID.allCases.count)
    }

    func testUnknownAndDuplicateWidgetsAreDropped() {
        defaults.set(["notes", "inconnu", "notes"], forKey: "prefs.widgetOrder")
        let prefs = makePreferences()
        XCTAssertEqual(prefs.widgetOrder.filter { $0 == .notes }.count, 1)
        XCTAssertEqual(prefs.widgetOrder.count, WidgetID.allCases.count)
    }

    func testOutOfRangeDelaysAreClamped() {
        defaults.set(99.0, forKey: "prefs.closeDelay")
        defaults.set(-1.0, forKey: "prefs.hoverOpenDelay")
        let prefs = makePreferences()
        XCTAssertEqual(prefs.closeDelay, 3.0)
        XCTAssertEqual(prefs.hoverOpenDelay, 0.05)
    }

    func testAllWidgetsDisabledInStoredDataFallsBackToAllEnabled() {
        defaults.set(WidgetID.allCases.map(\.rawValue), forKey: "prefs.disabledWidgets")
        let prefs = makePreferences()
        XCTAssertEqual(prefs.visibleWidgets.count, WidgetID.allCases.count)
    }

    func testNoAnimationMeansNoShrinkDelay() {
        let prefs = makePreferences()
        prefs.animationStyle = .none
        XCTAssertNil(prefs.animation)
        XCTAssertEqual(prefs.shrinkDelay, .zero)
    }
}
