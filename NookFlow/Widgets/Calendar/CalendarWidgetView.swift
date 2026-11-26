import SwiftUI
import AppKit

/// Date et heure, mois en cours, et prochains événements.
/// La date, l'heure et la grille du mois fonctionnent même sans accès au calendrier.
struct CalendarWidgetView: View {
    let model: CalendarModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            monthPane
                .frame(width: 180)
            rightPane
        }
        .onAppear { model.refresh() }
    }

    // MARK: - Mois

    private var monthPane: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(model.displayedMonth.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                iconButton("chevron.left", label: "Mois précédent") { model.shiftMonth(by: -1) }
                iconButton("circle.fill", label: "Revenir à aujourd'hui", size: 6) { model.goToToday() }
                    .opacity(model.isShowingCurrentMonth ? 0.3 : 1)
                iconButton("chevron.right", label: "Mois suivant") { model.shiftMonth(by: 1) }
            }

            HStack(spacing: 0) {
                ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(model.monthCells().enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 17)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = model.isToday(day)
        let isSelected = model.isSelected(day)

        return Button {
            model.toggleSelection(of: day)
        } label: {
            Text("\(model.dayNumber(day))")
                .font(.system(size: 10, weight: isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? Color.black : Color.white)
                .frame(width: 20, height: 17)
                .background(
                    Capsule().fill(isToday ? Color.white : Color.white.opacity(isSelected ? 0.22 : 0))
                )
                .overlay(alignment: .bottom) {
                    if model.hasEvents(on: day) {
                        Circle()
                            .fill(isToday ? Color.black : Color.orange)
                            .frame(width: 3, height: 3)
                            .offset(y: -0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconButton(_ name: String, label: String, size: CGFloat = 10, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Date, heure et événements

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Rafraîchi une fois par minute, uniquement tant que le panneau est ouvert.
            TimelineView(.everyMinute) { context in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            eventsArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var eventsArea: some View {
        switch model.access {
        case .notDetermined:
            message(
                "NookFlow peut afficher tes prochains événements. L'accès reste local : rien n'est envoyé ni modifié.",
                button: "Autoriser l'accès au calendrier"
            ) {
                Task { await model.requestAccess() }
            }
        case .denied:
            message(
                "Accès au calendrier refusé. Tu peux l'autoriser dans Réglages Système > Confidentialité et sécurité > Calendriers.",
                button: "Ouvrir les Réglages"
            ) {
                openPrivacySettings()
            }
        case .restricted:
            message("L'accès au calendrier est restreint sur ce Mac (profil de gestion ou contrôle parental).", button: nil) {}
        case .authorized:
            eventList
        }
    }

    @ViewBuilder
    private var eventList: some View {
        if let day = model.selectedDay {
            let events = model.events(on: day)
            list(groups: [CalendarModel.DayGroup(day: day, events: events)], emptyText: "Aucun événement ce jour-là")
        } else {
            list(groups: model.upcomingGroups(), emptyText: "Aucun événement dans les 7 prochains jours")
        }
    }

    private func list(groups: [CalendarModel.DayGroup], emptyText: String) -> some View {
        Group {
            if groups.allSatisfy({ $0.events.isEmpty }) {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.dayTitle(group.day))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                ForEach(group.events) { event in
                                    eventRow(event)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.timeText(for: event))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(model.timeText(for: event))")
    }

    private func message(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button, action: action)
                    .buttonStyle(NookPillStyle(prominent: true, compact: true))
            }
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
