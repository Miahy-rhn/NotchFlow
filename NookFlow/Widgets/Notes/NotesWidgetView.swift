import SwiftUI

struct NotesWidgetView: View {
    let store: NotesStore
    let state: NotchState

    @FocusState private var editorFocused: Bool
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 10) {
            sidebar
                .frame(width: 150)
            editorPane
        }
        // Toucher la zone des notes demande l'accès clavier au panneau (voir NotchPanel).
        .simultaneousGesture(TapGesture().onEnded { state.requestKeyboard() })
        .onChange(of: state.keyboardGrantCount) { _, _ in editorFocused = true }
        .onChange(of: store.selectedID) { _, _ in confirmingDelete = false }
    }

    // MARK: - Liste

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button {
                    store.createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .help("Nouvelle note")
                .accessibilityLabel("Nouvelle note")
            }

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(store.sortedNotes) { note in
                        noteRow(note)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func noteRow(_ note: NotesStore.Note) -> some View {
        let isSelected = note.id == store.selectedID
        return Button {
            store.select(note.id)
        } label: {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                Text(note.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(note.isEmpty ? .white.opacity(0.4) : .white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.16 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Éditeur

    @ViewBuilder
    private var editorPane: some View {
        if let id = store.selectedID, let note = store.note(id: id) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Button {
                        store.togglePin(id: id)
                    } label: {
                        Image(systemName: note.isPinned ? "pin.fill" : "pin")
                            .foregroundStyle(note.isPinned ? .orange : .white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help(note.isPinned ? "Désépingler" : "Épingler (visible dans la barre d'onglets)")
                    .accessibilityLabel(note.isPinned ? "Désépingler la note" : "Épingler la note")

                    if let error = store.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }

                    Spacer()

                    deleteControls(id: id)
                }
                .font(.caption)

                TextEditor(text: Binding(
                    get: { store.note(id: id)?.text ?? "" },
                    set: { store.update(id: id, text: $0) }
                ))
                .focused($editorFocused)
                .font(.callout)
                .foregroundStyle(.white)
                .tint(.white)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                .accessibilityLabel("Contenu de la note")
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                Text("Aucune note")
                    .font(.caption)
                Button("Nouvelle note") { store.createNote() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Confirmation en deux clics, sans boîte de dialogue : plus fiable dans un panneau flottant.
    @ViewBuilder
    private func deleteControls(id: UUID) -> some View {
        if confirmingDelete {
            HStack(spacing: 8) {
                Text("Supprimer cette note ?")
                    .foregroundStyle(.white.opacity(0.7))
                Button("Supprimer", role: .destructive) {
                    store.delete(id: id)
                    confirmingDelete = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                Button("Annuler") { confirmingDelete = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else {
            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Supprimer la note")
            .accessibilityLabel("Supprimer la note")
        }
    }
}
