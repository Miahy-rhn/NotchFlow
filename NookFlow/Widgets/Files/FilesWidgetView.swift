import SwiftUI
import AppKit

/// Zone de dépôt : affiche les fichiers déposés et permet de les ouvrir, les retirer
/// de la liste ou les glisser vers une autre application.
struct FilesWidgetView: View {
    let store: FileShelfStore
    let isDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ZStack {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    shelf
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isDropTargeted ? 0.14 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.white.opacity(0.12),
                        style: StrokeStyle(
                            lineWidth: isDropTargeted ? 2 : 1,
                            dash: store.entries.isEmpty ? [5, 4] : []
                        )
                    )
            )
        }
    }

    // MARK: - Parties

    private var header: some View {
        HStack(spacing: 8) {
            Label("Dépôt de fichiers", systemImage: "tray.full")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            if !store.entries.isEmpty {
                Text("\(store.entries.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let message = store.lastError {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            Spacer()

            if !store.entries.isEmpty {
                Button("Vider") { store.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHint("Retire tous les fichiers de la liste, sans les supprimer du Mac")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.title2)
            Text(isDropTargeted ? "Relâche pour ajouter" : "Dépose des fichiers ici")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.65))
        .accessibilityElement(children: .combine)
    }

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.entries) { entry in
                    FileTile(entry: entry) { store.remove(entry.id) }
                }
            }
            .padding(8)
        }
    }
}

private struct FileTile: View {
    let entry: FileShelfStore.Entry
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 40, height: 40)
                .opacity(entry.isMissing ? 0.35 : 1)

            Text(entry.name)
                .font(.caption2)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)

            Text(entry.detail)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(width: 84)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isHovering ? 0.1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8), .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Retirer de la liste")
                .accessibilityLabel("Retirer \(entry.name) de la liste")
            }
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { open() }
        .onDrag {
            // Glisser vers une autre app : l'app de destination décide de copier ou de déplacer.
            // NookFlow, lui, ne modifie jamais le fichier.
            if entry.isMissing { return NSItemProvider() }
            return NSItemProvider(contentsOf: entry.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Ouvrir") { open() }
                .disabled(entry.isMissing)
            Button("Afficher dans le Finder") { reveal() }
                .disabled(entry.isMissing)
            Divider()
            Button("Retirer de la liste", action: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(entry.detail)")
        .accessibilityAction(named: "Ouvrir") { open() }
        .accessibilityAction(named: "Retirer de la liste") { onRemove() }
    }

    private func open() {
        guard !entry.isMissing else { return }
        NSWorkspace.shared.open(entry.url)
    }

    private func reveal() {
        guard !entry.isMissing else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }
}
