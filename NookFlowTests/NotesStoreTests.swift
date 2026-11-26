import XCTest
@testable import NookFlow

@MainActor
final class NotesStoreTests: XCTestCase {
    private var storageURL: URL!
    private var current = Date(timeIntervalSince1970: 0)

    override func setUp() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nookflow-tests-\(UUID().uuidString)")
        storageURL = folder.appendingPathComponent("notes.json")
        current = Date(timeIntervalSince1970: 0)
        let folderToRemove = folder
        addTeardownBlock { try? FileManager.default.removeItem(at: folderToRemove) }
    }

    private func makeStore() -> NotesStore {
        NotesStore(storageURL: storageURL, now: { [unowned self] in
            self.current = self.current.addingTimeInterval(1) // chaque appel avance d'une seconde
            return self.current
        })
    }

    /// Crée une note avec ce texte et renvoie son identifiant.
    @discardableResult
    private func addNote(_ text: String, to store: NotesStore) -> UUID {
        store.createNote()
        let id = store.selectedID!
        store.update(id: id, text: text)
        return id
    }

    func testCreateSelectsNewNote() {
        let store = makeStore()
        store.createNote()
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.selectedID, store.notes[0].id)
    }

    func testNotesSurviveRestart() {
        let store = makeStore()
        addNote("Bonjour\nle monde", to: store)
        store.flush() // simule la sortie de l'app

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes[0].text, "Bonjour\nle monde")
        XCTAssertEqual(reloaded.notes[0].title, "Bonjour")
    }

    func testOnlyOneNoteCanBePinned() {
        let store = makeStore()
        let first = addNote("A", to: store)
        let second = addNote("B", to: store)

        store.togglePin(id: first)
        store.togglePin(id: second)

        XCTAssertEqual(store.notes.filter(\.isPinned).count, 1)
        XCTAssertEqual(store.pinnedNote?.id, second)
        XCTAssertEqual(store.sortedNotes.first?.id, second)
    }

    func testTogglePinTwiceUnpins() {
        let store = makeStore()
        let id = addNote("A", to: store)
        store.togglePin(id: id)
        store.togglePin(id: id)
        XCTAssertNil(store.pinnedNote)
    }

    func testDeleteSelectsAnotherNote() {
        let store = makeStore()
        let first = addNote("A", to: store)
        let second = addNote("B", to: store)

        store.delete(id: second)

        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.selectedID, first)
    }

    func testDeleteIsWrittenImmediately() {
        let store = makeStore()
        let id = addNote("A", to: store)
        store.flush()
        store.delete(id: id)

        XCTAssertTrue(makeStore().notes.isEmpty)
    }

    func testEmptyNoteIsRemovedWhenLeavingIt() {
        let store = makeStore()
        store.createNote() // reste vide
        let emptyID = store.selectedID!
        store.createNote()

        XCTAssertNil(store.note(id: emptyID))
        XCTAssertEqual(store.notes.count, 1)
    }

    func testMostRecentlyEditedNoteComesFirst() {
        let store = makeStore()
        let older = addNote("Ancienne", to: store)
        let newer = addNote("Récente", to: store)
        XCTAssertEqual(store.sortedNotes.map(\.id), [newer, older])

        store.update(id: older, text: "Ancienne modifiée")
        XCTAssertEqual(store.sortedNotes.first?.id, older)
    }

    func testTitleOfBlankNote() {
        let note = NotesStore.Note(id: UUID(), text: "  \n ", updatedAt: Date(), isPinned: false)
        XCTAssertEqual(note.title, "Note vide")
        XCTAssertTrue(note.isEmpty)
    }

    func testCorruptedFileReportsErrorInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("pas du json".utf8).write(to: storageURL)

        let store = makeStore()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNotNil(store.lastError)
    }
}
