import AppKit
import EventKit
import Foundation

enum CalendarAccess: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let color: NSColor
    let location: String?
}

/// Ce dont le widget a besoin pour lire le calendrier. Un protocole simple permet
/// de le remplacer par de fausses données dans les tests.
@MainActor
protocol CalendarProviding: AnyObject {
    var access: CalendarAccess { get }
    /// Appelé quand le calendrier de l'utilisateur change (événement ajouté, modifié, supprimé…).
    var onStoreChange: (() -> Void)? { get set }
    func requestAccess() async -> Bool
    func events(from start: Date, to end: Date) -> [CalendarEvent]
}

/// Lecture seule du calendrier via EventKit. Rien n'est écrit, rien ne quitte le Mac.
@MainActor
final class EventKitCalendarService: CalendarProviding {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol? // vit aussi longtemps que l'app
    var onStoreChange: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onStoreChange?() }
        }
    }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied // refusé, ou accès en écriture seule (insuffisant pour lire)
        }
    }

    /// À appeler uniquement après une action explicite de l'utilisateur.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map { event in
                let color: NSColor = event.calendar?.color ?? .systemBlue
                // Un événement récurrent garde le même identifiant à chaque occurrence :
                // on ajoute la date de début pour obtenir un identifiant unique.
                let baseID = event.eventIdentifier ?? UUID().uuidString
                return CalendarEvent(
                    id: "\(baseID)-\(Int(event.startDate.timeIntervalSince1970))",
                    title: event.title ?? "Sans titre",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar?.title ?? "",
                    color: color,
                    location: event.location
                )
            }
            .sorted { $0.start < $1.start }
    }
}
