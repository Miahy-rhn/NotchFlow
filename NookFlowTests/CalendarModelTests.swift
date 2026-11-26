import AppKit
import XCTest
@testable import NookFlow

@MainActor
final class FakeCalendarService: CalendarProviding {
    var access: CalendarAccess
    var onStoreChange: (() -> Void)?
    var stored: [CalendarEvent] = []
    var grantsAccess = true
    private(set) var eventsCalls = 0

    init(access: CalendarAccess) { self.access = access }

    func requestAccess() async -> Bool {
        if grantsAccess { access = .authorized }
        return grantsAccess
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        eventsCalls += 1
        return stored.filter { $0.start < end && $0.end > start }
    }
}

@MainActor
final class CalendarModelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // lundi
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, from start: Date, to end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(
            id: id, title: id, start: start, end: end, isAllDay: allDay,
            calendarTitle: "Test", color: .systemBlue, location: nil
        )
    }

    /// « Maintenant » fixé au mercredi 28 octobre 2026, 12:00.
    private func makeModel(_ service: FakeCalendarService) -> CalendarModel {
        let now = date(2026, 10, 28, 12)
        return CalendarModel(service: service, calendar: calendar, now: { now })
    }

    // MARK: - Grille

    func testOctober2026GridStartsOnThursdayWithMondayFirst() {
        let model = makeModel(FakeCalendarService(access: .authorized))
        let cells = model.monthCells()

        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(cells.firstIndex { $0 != nil }, 3) // lun, mar, mer vides : le 1er est un jeudi
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
    }

    func testWeekdaySymbolsStartOnMonday() {
        let model = makeModel(FakeCalendarService(access: .authorized))
        XCTAssertEqual(model.weekdaySymbols.count, 7)
        XCTAssertEqual(model.weekdaySymbols.first, "M")
        XCTAssertEqual(model.weekdaySymbols.last, "S")
    }

    func testTodayIsDetectedWithInjectedClock() {
        let model = makeModel(FakeCalendarService(access: .authorized))
        XCTAssertTrue(model.isToday(date(2026, 10, 28, 3)))
        XCTAssertFalse(model.isToday(date(2026, 10, 29)))
    }

    // MARK: - Autorisation

    func testNothingIsReadWithoutAuthorization() {
        for access in [CalendarAccess.notDetermined, .denied, .restricted] {
            let service = FakeCalendarService(access: access)
            service.stored = [event("A", from: date(2026, 10, 28, 15), to: date(2026, 10, 28, 16))]
            let model = makeModel(service)

            XCTAssertEqual(service.eventsCalls, 0, "lecture inattendue avec l'accès \(access)")
            XCTAssertTrue(model.upcoming.isEmpty)
            XCTAssertTrue(model.monthEvents.isEmpty)
        }
    }

    func testRequestAccessLoadsEvents() async {
        let service = FakeCalendarService(access: .notDetermined)
        service.stored = [event("A", from: date(2026, 10, 28, 15), to: date(2026, 10, 28, 16))]
        let model = makeModel(service)

        await model.requestAccess()

        XCTAssertEqual(model.access, .authorized)
        XCTAssertEqual(model.upcoming.map(\.id), ["A"])
    }

    func testRefusedAccessStaysEmpty() async {
        let service = FakeCalendarService(access: .notDetermined)
        service.grantsAccess = false
        let model = makeModel(service)

        await model.requestAccess()

        XCTAssertEqual(model.access, .notDetermined)
        XCTAssertTrue(model.upcoming.isEmpty)
    }

    func testDisabledModelReadsNothingUntilReactivated() {
        let service = FakeCalendarService(access: .authorized)
        service.stored = [event("A", from: date(2026, 10, 28, 15), to: date(2026, 10, 28, 16))]
        let now = date(2026, 10, 28, 12)
        let model = CalendarModel(service: service, calendar: calendar, now: { now }, isActive: false)

        model.refresh()
        XCTAssertEqual(service.eventsCalls, 0)
        XCTAssertTrue(model.upcoming.isEmpty)

        model.isActive = true
        model.refresh()
        XCTAssertEqual(model.upcoming.map(\.id), ["A"])
    }

    // MARK: - Événements

    func testUpcomingIsGroupedByDayAndOngoingEventsAreUnderToday() {
        let service = FakeCalendarService(access: .authorized)
        service.stored = [
            event("B", from: date(2026, 10, 29, 9), to: date(2026, 10, 29, 10)),
            event("A", from: date(2026, 10, 28, 15), to: date(2026, 10, 28, 16)),
            event("C", from: date(2026, 10, 27, 22), to: date(2026, 10, 28, 13)), // commencé hier, en cours
            event("Passé", from: date(2026, 10, 28, 8), to: date(2026, 10, 28, 9)), // déjà terminé
            event("Trop loin", from: date(2026, 11, 20, 9), to: date(2026, 11, 20, 10))
        ]
        let model = makeModel(service)
        let groups = model.upcomingGroups()

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].events.map(\.id), ["C", "A"])
        XCTAssertEqual(groups[1].events.map(\.id), ["B"])
    }

    func testDaysWithEventsAreMarked() {
        let service = FakeCalendarService(access: .authorized)
        service.stored = [event("A", from: date(2026, 10, 30, 9), to: date(2026, 10, 30, 10))]
        let model = makeModel(service)

        XCTAssertTrue(model.hasEvents(on: date(2026, 10, 30)))
        XCTAssertFalse(model.hasEvents(on: date(2026, 10, 29)))
    }

    func testMultiDayEventAppearsOnEachDay() {
        let service = FakeCalendarService(access: .authorized)
        service.stored = [event("Voyage", from: date(2026, 10, 12), to: date(2026, 10, 15), allDay: true)]
        let model = makeModel(service)

        XCTAssertTrue(model.hasEvents(on: date(2026, 10, 12)))
        XCTAssertTrue(model.hasEvents(on: date(2026, 10, 14)))
        XCTAssertFalse(model.hasEvents(on: date(2026, 10, 15))) // la fin est exclusive
    }

    // MARK: - Navigation

    func testSelectingSameDayTwiceClearsSelection() {
        let model = makeModel(FakeCalendarService(access: .authorized))
        let day = date(2026, 10, 30)

        model.toggleSelection(of: day)
        XCTAssertTrue(model.isSelected(day))
        model.toggleSelection(of: day)
        XCTAssertNil(model.selectedDay)
    }

    func testShiftMonthAndGoBackToToday() {
        let model = makeModel(FakeCalendarService(access: .authorized))

        model.shiftMonth(by: 1)
        XCTAssertEqual(calendar.component(.month, from: model.displayedMonth), 11)
        XCTAssertFalse(model.isShowingCurrentMonth)

        model.goToToday()
        XCTAssertEqual(calendar.component(.month, from: model.displayedMonth), 10)
        XCTAssertTrue(model.isShowingCurrentMonth)
    }

    func testTimeTextForAllDayEvent() {
        let model = makeModel(FakeCalendarService(access: .authorized))
        let allDay = event("X", from: date(2026, 10, 28), to: date(2026, 10, 29), allDay: true)
        XCTAssertEqual(model.timeText(for: allDay), "Toute la journée")
    }
}
