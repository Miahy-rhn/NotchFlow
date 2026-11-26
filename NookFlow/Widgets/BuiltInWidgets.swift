import SwiftUI

// Les cinq widgets de NookFlow. Chacun relie un modèle de données à sa vue.

@MainActor
final class FilesWidget: NookWidget {
    let id = WidgetID.files
    private let store: FileShelfStore
    init(store: FileShelfStore) { self.store = store }

    // Les fichiers ont pu être déplacés ou supprimés depuis la dernière ouverture.
    func panelWillExpand() { store.refresh() }

    func makeView(state: NotchState) -> AnyView {
        AnyView(FilesWidgetView(store: store, isDropTargeted: state.isDropTargeted))
    }
}

@MainActor
final class NotesWidget: NookWidget {
    let id = WidgetID.notes
    let wantsKeyboard = true
    private let store: NotesStore
    init(store: NotesStore) { self.store = store }

    func makeView(state: NotchState) -> AnyView {
        AnyView(NotesWidgetView(store: store, state: state))
    }
}

@MainActor
final class TimerWidget: NookWidget {
    let id = WidgetID.timer
    private let timer: TimerModel
    init(timer: TimerModel) { self.timer = timer }

    func makeView(state: NotchState) -> AnyView {
        AnyView(TimerWidgetView(timer: timer))
    }
}

@MainActor
final class CalendarWidget: NookWidget {
    let id = WidgetID.calendar
    private let model: CalendarModel
    init(model: CalendarModel) { self.model = model }

    // Un widget désactivé n'accède plus à ses données (le modèle ignore refresh() s'il est inactif).
    func panelWillExpand() { model.refresh() }

    func enabledChanged(_ enabled: Bool) {
        let wasActive = model.isActive
        model.isActive = enabled
        if enabled && !wasActive { model.refresh() }
    }

    func makeView(state: NotchState) -> AnyView {
        AnyView(CalendarWidgetView(model: model))
    }
}

@MainActor
final class MusicWidget: NookWidget {
    let id = WidgetID.music
    private let model: NowPlayingModel
    init(model: NowPlayingModel) { self.model = model }

    func makeView(state: NotchState) -> AnyView {
        AnyView(MusicWidgetView(model: model))
    }

    /// Pochette floutée quand Spotify en fournit une.
    func backdrop(notchHeight: CGFloat) -> AnyView? {
        guard model.playerState != .stopped, let artwork = model.artwork else { return nil }
        return AnyView(MusicBackdrop(image: artwork, notchHeight: notchHeight))
    }
}
