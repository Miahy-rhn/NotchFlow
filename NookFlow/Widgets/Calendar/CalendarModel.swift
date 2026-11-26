import Foundation
import Observation

/// Logique du widget calendrier : mois affiché, jour sélectionné, événements à venir.
/// Aucune horloge ni boucle : tout est recalculé à la demande (ouverture du panneau,
/// changement de mois, modification du calendrier).
@MainActor
@Observable
final class CalendarModel {
    struct DayGroup: Identifiable {
        let day: Date
        let events: [CalendarEvent]
        var id: Date { day }
    }

    private(set) var access: CalendarAccess
    private(set) var upcoming: [CalendarEvent] = []
    private(set) var monthEvents: [CalendarEvent] = []
    private(set) var displayedMonth: Date
    private(set) var selectedDay: Date?

    /// Faux quand le widget est désactivé dans les préférences : plus aucune lecture du calendrier.
    @ObservationIgnored var isActive: Bool

    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let service: CalendarProviding
    @ObservationIgnored private let now: () -> Date

    init(
        service: CalendarProviding,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() },
        isActive: Bool = true
    ) {
        self.isActive = isActive
        self.service = service
        self.calendar = calendar
        self.now = now
        self.access = service.access
        self.displayedMonth = Self.startOfMonth(for: now(), calendar: calendar)
        service.onStoreChange = { [weak self] in self?.refresh() }
        refresh()
    }

    // MARK: - Données

    /// Relit l'état de l'autorisation et les événements. Sans autorisation, ne lit rien.
    func refresh() {
        guard isActive else { return }
        access = service.access
        guard access == .authorized else {
            upcoming = []
            monthEvents = []
            return
        }

        let current = now()
        let weekLater = calendar.date(byAdding: .day, value: 7, to: current) ?? current
        upcoming = service.events(from: current, to: weekLater).filter { $0.end > current }

        if let interval = calendar.dateInterval(of: .month, for: displayedMonth) {
            monthEvents = service.events(from: interval.start, to: interval.end)
        }
    }

    /// Demande l'autorisation (appelée après un clic de l'utilisateur), puis recharge.
    func requestAccess() async {
        _ = await service.requestAccess()
        refresh()
    }

    // MARK: - Navigation

    func shiftMonth(by months: Int) {
        guard let moved = calendar.date(byAdding: .month, value: months, to: displayedMonth) else { return }
        displayedMonth = Self.startOfMonth(for: moved, calendar: calendar)
        selectedDay = nil
        refresh()
    }

    func goToToday() {
        displayedMonth = Self.startOfMonth(for: now(), calendar: calendar)
        selectedDay = nil
        refresh()
    }

    /// Un second clic sur le jour sélectionné revient à la liste « à venir ».
    func toggleSelection(of day: Date) {
        if let selectedDay, calendar.isDate(selectedDay, inSameDayAs: day) {
            self.selectedDay = nil
        } else {
            selectedDay = day
        }
    }

    var isShowingCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: now(), toGranularity: .month)
    }

    // MARK: - Grille du mois

    /// 42 cases (6 semaines) pour que la hauteur reste stable ; `nil` = case vide.
    func monthCells() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    /// Initiales des jours, dans l'ordre de la semaine locale (lundi d'abord en France).
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    func dayNumber(_ day: Date) -> Int { calendar.component(.day, from: day) }
    func isToday(_ day: Date) -> Bool { calendar.isDate(day, inSameDayAs: now()) }

    func isSelected(_ day: Date) -> Bool {
        guard let selectedDay else { return false }
        return calendar.isDate(selectedDay, inSameDayAs: day)
    }

    func hasEvents(on day: Date) -> Bool { !events(on: day).isEmpty }

    func events(on day: Date) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return monthEvents.filter { $0.start < dayEnd && $0.end > dayStart }
    }

    // MARK: - Listes affichées

    /// Événements des 7 prochains jours, regroupés par jour (un événement déjà commencé
    /// est rangé sous « Aujourd'hui »).
    func upcomingGroups() -> [DayGroup] {
        let today = calendar.startOfDay(for: now())
        let grouped = Dictionary(grouping: upcoming) { event in
            max(calendar.startOfDay(for: event.start), today)
        }
        return grouped
            .map { DayGroup(day: $0.key, events: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.day < $1.day }
    }

    func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInTomorrow(day) { return "Demain" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    func timeText(for event: CalendarEvent) -> String {
        if event.isAllDay { return "Toute la journée" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    // MARK: - Interne

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}
