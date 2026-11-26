import Foundation
import Observation

/// Liste temporaire de fichiers déposés dans NookFlow.
///
/// Règles importantes :
/// - on ne stocke que des *références* (bookmarks) : les fichiers originaux ne sont
///   jamais copiés, déplacés ni supprimés par l'app ;
/// - un bookmark suit le fichier s'il est renommé ou déplacé dans le Finder ;
/// - si le fichier n'existe plus, l'entrée reste visible comme « Introuvable »
///   jusqu'à ce que l'utilisateur la retire.
@MainActor
@Observable
final class FileShelfStore {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let url: URL
        let kind: String
        let size: Int64?
        let isMissing: Bool

        var name: String { url.lastPathComponent }

        var detail: String {
            if isMissing { return "Introuvable" }
            guard let size else { return kind }
            return "\(kind) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        }
    }

    /// Ce qui est réellement écrit sur disque.
    private struct StoredItem: Codable {
        let id: UUID
        var bookmark: Data
        var lastKnownPath: String
    }

    private(set) var entries: [Entry] = []
    /// Dernier message d'erreur compréhensible, affiché dans le widget.
    var lastError: String?

    @ObservationIgnored private var items: [StoredItem] = []
    @ObservationIgnored private let storageURL: URL

    nonisolated static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NookFlow/file-shelf.json")
    }

    init(storageURL: URL = FileShelfStore.defaultStorageURL) {
        self.storageURL = storageURL
        load()
        refresh()
    }

    // MARK: - Actions

    /// Ajoute des fichiers ou dossiers à la liste. Les doublons sont ignorés.
    /// Renvoie `true` si le dépôt contenait au moins un fichier local.
    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !fileURLs.isEmpty else { return false }

        lastError = nil
        var failures = 0
        for url in fileURLs {
            // Comparaison sur le chemin réel : /var et /private/var désignent le même fichier.
            let canonical = url.resolvingSymlinksInPath().path
            let alreadyListed = items.contains {
                URL(fileURLWithPath: $0.lastKnownPath).resolvingSymlinksInPath().path == canonical
            }
            if alreadyListed { continue }

            do {
                let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                items.insert(StoredItem(id: UUID(), bookmark: bookmark, lastKnownPath: url.path), at: 0)
            } catch {
                failures += 1
            }
        }

        if failures > 0 {
            lastError = failures == 1
                ? "1 élément n'a pas pu être ajouté."
                : "\(failures) éléments n'ont pas pu être ajoutés."
        }
        save()
        refresh()
        return true
    }

    /// Retire une entrée de la liste. Le fichier original n'est pas touché.
    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        entries.removeAll { $0.id == id }
        save()
    }

    /// Vide la liste. Les fichiers originaux ne sont pas touchés.
    func clear() {
        items.removeAll()
        entries.removeAll()
        lastError = nil
        save()
    }

    /// Re-résout chaque bookmark : détecte les fichiers déplacés, renommés ou supprimés.
    func refresh() {
        var newEntries: [Entry] = []
        var needsSave = false

        for index in items.indices {
            let item = items[index]
            var isStale = false
            let resolved = try? URL(
                resolvingBookmarkData: item.bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if let url = resolved, FileManager.default.fileExists(atPath: url.path) {
                if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    items[index].bookmark = fresh
                    needsSave = true
                }
                if items[index].lastKnownPath != url.path {
                    items[index].lastKnownPath = url.path
                    needsSave = true
                }

                let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey])
                let isDirectory = values?.isDirectory == true
                var size: Int64?
                if !isDirectory, let bytes = values?.fileSize { size = Int64(bytes) }

                newEntries.append(Entry(
                    id: item.id,
                    url: url,
                    kind: values?.localizedTypeDescription ?? "Fichier",
                    size: size,
                    isMissing: false
                ))
            } else {
                newEntries.append(Entry(
                    id: item.id,
                    url: URL(fileURLWithPath: item.lastKnownPath),
                    kind: "Introuvable",
                    size: nil,
                    isMissing: true
                ))
            }
        }

        entries = newEntries
        if needsSave { save() }
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            items = try JSONDecoder().decode([StoredItem].self, from: data)
        } catch {
            lastError = "La liste de fichiers n'a pas pu être relue : \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Impossible d'enregistrer la liste : \(error.localizedDescription)"
        }
    }
}
