import XCTest
@testable import NookFlow

@MainActor
final class FileShelfStoreTests: XCTestCase {
    private var folder: URL!
    private var storageURL: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("nookflow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("shelf.json")
        let folderToRemove = folder!
        addTeardownBlock { try? FileManager.default.removeItem(at: folderToRemove) }
    }

    private func makeFile(_ name: String, contents: String = "hello") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func makeStore() -> FileShelfStore {
        FileShelfStore(storageURL: storageURL)
    }

    func testAddShowsNameAndSize() throws {
        let file = try makeFile("rapport.txt")
        let store = makeStore()

        XCTAssertTrue(store.add([file]))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].name, "rapport.txt")
        XCTAssertEqual(store.entries[0].size, 5)
        XCTAssertFalse(store.entries[0].isMissing)
    }

    func testDuplicatesAreIgnored() throws {
        let file = try makeFile("a.txt")
        let store = makeStore()
        store.add([file])
        store.add([file])
        XCTAssertEqual(store.entries.count, 1)
    }

    func testRemoveNeverTouchesTheOriginalFile() throws {
        let file = try makeFile("a.txt")
        let store = makeStore()
        store.add([file])

        store.remove(store.entries[0].id)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testClearNeverTouchesOriginalFiles() throws {
        let first = try makeFile("a.txt")
        let second = try makeFile("b.txt")
        let store = makeStore()
        store.add([first, second])

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testListSurvivesRestart() throws {
        let file = try makeFile("a.txt")
        makeStore().add([file])

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries[0].name, "a.txt")
    }

    func testRenamedFileIsFollowed() throws {
        let file = try makeFile("avant.txt")
        let store = makeStore()
        store.add([file])

        let renamed = folder.appendingPathComponent("apres.txt")
        try FileManager.default.moveItem(at: file, to: renamed)
        store.refresh()

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].name, "apres.txt")
        XCTAssertFalse(store.entries[0].isMissing)
    }

    func testDeletedFileIsReportedAsMissingButKept() throws {
        let file = try makeFile("a.txt")
        let store = makeStore()
        store.add([file])

        try FileManager.default.removeItem(at: file)
        store.refresh()

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(store.entries[0].isMissing)
        XCTAssertEqual(store.entries[0].detail, "Introuvable")
    }

    func testNonFileURLsAreRejected() {
        let store = makeStore()
        XCTAssertFalse(store.add([URL(string: "https://example.com")!]))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testFoldersAreAcceptedWithoutSize() throws {
        let subfolder = folder.appendingPathComponent("dossier")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let store = makeStore()

        XCTAssertTrue(store.add([subfolder]))
        XCTAssertNil(store.entries[0].size)
    }
}
