import SwiftUI
import XCTest
@testable import NookFlow

@MainActor
private final class FakeWidget: NookWidget {
    let id: WidgetID
    let wantsKeyboard: Bool
    private(set) var expandCount = 0
    private(set) var enabledCalls: [Bool] = []

    init(_ id: WidgetID, wantsKeyboard: Bool = false) {
        self.id = id
        self.wantsKeyboard = wantsKeyboard
    }

    func panelWillExpand() { expandCount += 1 }
    func enabledChanged(_ enabled: Bool) { enabledCalls.append(enabled) }
    func makeView(state: NotchState) -> AnyView { AnyView(EmptyView()) }
}

@MainActor
final class WidgetRegistryTests: XCTestCase {
    private func allFakes() -> [WidgetID: FakeWidget] {
        Dictionary(uniqueKeysWithValues: WidgetID.allCases.map { ($0, FakeWidget($0, wantsKeyboard: $0 == .notes)) })
    }

    func testMissingWidgetsListsWhatIsNotRegistered() {
        let registry = WidgetRegistry([FakeWidget(.files), FakeWidget(.timer)])
        XCTAssertEqual(Set(registry.missingWidgets), [.notes, .calendar, .music])

        let complete = WidgetRegistry(Array(allFakes().values))
        XCTAssertTrue(complete.missingWidgets.isEmpty)
    }

    func testKeyboardWidgetsComeFromTheWidgets() {
        let registry = WidgetRegistry(Array(allFakes().values))
        XCTAssertEqual(registry.keyboardWidgets, [.notes])
    }

    func testPanelWillExpandOnlyTouchesEnabledWidgets() {
        let fakes = allFakes()
        let registry = WidgetRegistry(Array(fakes.values))

        registry.panelWillExpand(isEnabled: { $0 != .calendar })

        XCTAssertEqual(fakes[.files]?.expandCount, 1)
        XCTAssertEqual(fakes[.music]?.expandCount, 1)
        XCTAssertEqual(fakes[.calendar]?.expandCount, 0) // désactivé : on n'y touche pas
    }

    func testSyncEnabledReachesEveryWidget() {
        let fakes = allFakes()
        let registry = WidgetRegistry(Array(fakes.values))

        registry.syncEnabled(isEnabled: { $0 != .timer })

        XCTAssertEqual(fakes[.timer]?.enabledCalls, [false])
        XCTAssertEqual(fakes[.files]?.enabledCalls, [true])
    }

    func testMissingViewFallsBackToEmptyView() {
        let registry = WidgetRegistry([])
        let state = NotchState(preferences: AppPreferences(defaults: makeIsolatedDefaults(self)))
        _ = registry.view(for: .files, state: state) // ne doit pas planter
    }

    func testCalendarWidgetActivatesAndRefreshesOnlyWhenEnabledChanges() {
        let service = FakeCalendarService(access: .authorized)
        let model = CalendarModel(service: service, isActive: false)
        let widget = CalendarWidget(model: model)

        widget.enabledChanged(false)
        XCTAssertEqual(service.eventsCalls, 0)

        widget.enabledChanged(true)
        XCTAssertTrue(model.isActive)
        let callsAfterEnable = service.eventsCalls
        XCTAssertGreaterThan(callsAfterEnable, 0)

        widget.enabledChanged(true) // aucun changement : aucune relecture
        XCTAssertEqual(service.eventsCalls, callsAfterEnable)

        widget.enabledChanged(false)
        XCTAssertFalse(model.isActive)
    }

    func testSelectingKeyboardWidgetRequestsKeyboardOnlyForThatWidget() {
        let state = NotchState(preferences: AppPreferences(defaults: makeIsolatedDefaults(self)))
        state.keyboardWidgets = [.notes]
        var requests: [Bool] = []
        state.setKeyboardAccess = { requests.append($0) }

        state.select(.notes)
        state.select(.files)

        XCTAssertEqual(requests, [true, false])
    }
}
