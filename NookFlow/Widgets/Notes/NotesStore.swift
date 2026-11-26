import Foundation
import Observation

/// Notes rapides, stockées localement dans un fichier JSON (aucune donnée ne quitte le Mac).
@MainActor
@Observable
final class NotesStore {
    struct Note: Identifiable, Codable, Equatable {
        let id: UUID
        var text: String
        var updatedAt: Date
        var isPinned: Bool

        /// Première ligne non vide, utilisée comme titre dans la liste.
        var title: String {
            let firstLine = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return firstLine ?? "Note vide"
        }

        var isEmpty: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private(set) var notes: [Note] = []
    private(set) var selectedID: UUID?
    var lastError: String?

    @ObservationIgnored private let storageURL: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    nonisolated static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NookFlow/notes.json")
    }

    init(storageURL: URL = NotesStore.defaultStorageURL, now: @escaping () -> Date = { Date() }) {
        self.storageURL = storageURL
        self.now = now
        load()
        selectedID = sortedNotes.first?.id
    }

    // MARK: - Lecture

    /// Note épinglée d'abord, puis les plus récentes.
    var sortedNotes: [Note] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var pinnedNote: Note? { notes.first { $0.isPinned } }

    func note(id: UUID) -> Note? { notes.first { $0.id == id } }

    // MARK: - Actions

    func createNote() {
        let note = Note(id: UUID(), text: "", updatedAt: now(), isPinned: false)
        notes.append(note)
        select(note.id)
        scheduleSave()
    }

    /// Sélectionne une note. Une note laissée vide est supprimée en la quittant.
    func select(_ id: UUID?) {
        let previous = selectedID
        selectedID = id
        if let previous, previous != id, let old = note(id: previous), old.isEmpty {
            notes.removeAll { $0.id == previous }
            scheduleSave()
        }
    }

    func update(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updatedAt = now()
        scheduleSave()
    }

    /// Une seule note peut être épinglée : épingler l'une désépingle les autres.
    func togglePin(id: UUID) {
        guard let target = note(id: id) else { return }
        let shouldPin = !target.isPinned
        for index in notes.indices { notes[index].isPinned = false }
        if let index = notes.firstIndex(where: { $0.id == id }) { notes[index].isPinned = shouldPin }
        scheduleSave()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedID == id { selectedID = sortedNotes.first?.id }
        saveNow()
    }

    /// À appeler avant de quitter l'app : écrit immédiatement les modifications en attente.
    func flush() {
        saveTask?.cancel()
        saveNow()
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = try decoder.decode([Note].self, from: data)
        } catch {
            lastError = "Les notes n'ont pas pu être relues : \(error.localizedDescription)"
        }
    }

    /// Écriture différée : pendant la frappe, on n'écrit qu'une fois la saisie calmée.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(notes).write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Impossible d'enregistrer les notes : \(error.localizedDescription)"
        }
    }
}
