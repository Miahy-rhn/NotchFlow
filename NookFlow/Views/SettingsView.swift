import SwiftUI

/// Fenêtre de préférences. Elle suit le thème clair ou sombre de macOS.
struct SettingsView: View {
    @Bindable var preferences: AppPreferences
    let launchAtLogin: LaunchAtLogin

    @State private var confirmingReset = false

    var body: some View {
        Form {
            widgetsSection
            behaviorSection
            appearanceSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 640)
        .onAppear { launchAtLogin.refresh() }
    }

    // MARK: - Widgets

    private var widgetsSection: some View {
        Section {
            ForEach(preferences.widgetOrder) { widget in
                HStack(spacing: 10) {
                    Image(systemName: widget.symbol)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)

                    Toggle(widget.title, isOn: Binding(
                        get: { preferences.isEnabled(widget) },
                        set: { preferences.setEnabled($0, for: widget) }
                    ))
                    .disabled(!preferences.canDisable(widget) && preferences.isEnabled(widget))

                    Spacer()

                    Button {
                        preferences.move(widget, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(preferences.widgetOrder.first == widget)
                    .accessibilityLabel("Monter \(widget.title)")

                    Button {
                        preferences.move(widget, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(preferences.widgetOrder.last == widget)
                    .accessibilityLabel("Descendre \(widget.title)")
                }
                .buttonStyle(.borderless)
            }

            Toggle("Toujours ouvrir sur le premier widget", isOn: $preferences.openOnFirstWidget)
        } header: {
            Text("Widgets")
        } footer: {
            Text("Le premier widget activé s'affiche en priorité. Au moins un widget doit rester activé. Un widget désactivé n'accède plus à ses données (par exemple, le calendrier n'est plus lu).")
        }
    }

    // MARK: - Ouverture et fermeture

    private var behaviorSection: some View {
        Section("Ouverture et fermeture") {
            Picker("Ouvrir le panneau par", selection: $preferences.openTrigger) {
                ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
            }

            if preferences.openTrigger == .hoverOrClick {
                LabeledContent("Délai d'ouverture") {
                    HStack {
                        Slider(value: $preferences.hoverOpenDelay, in: 0.05...1.0, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int(preferences.hoverOpenDelay * 1000)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            }

            Toggle("Fermer automatiquement quand le pointeur s'éloigne", isOn: $preferences.autoClose)

            if preferences.autoClose {
                LabeledContent("Délai de fermeture") {
                    HStack {
                        Slider(value: $preferences.closeDelay, in: 0.2...3.0, step: 0.1)
                            .frame(width: 180)
                        Text(String(format: "%.1f s", preferences.closeDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            } else {
                Text("Sans fermeture automatique, referme le panneau avec la flèche en haut à droite, le clic droit ou le menu de la barre des menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Apparence

    private var appearanceSection: some View {
        Section {
            LabeledContent("Thème") {
                HStack(spacing: 10) {
                    ForEach(NookTheme.allCases) { theme in
                        let isSelected = preferences.theme == theme
                        Button {
                            preferences.theme = theme
                        } label: {
                            Circle()
                                .fill(theme.color)
                                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                                .frame(width: 26, height: 26)
                                .padding(3)
                                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .help(theme.title)
                        .accessibilityLabel(theme.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            Picker("Animations", selection: $preferences.animationStyle) {
                ForEach(AnimationStyle.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Apparence")
        } footer: {
            Text("Le panneau réduit reste noir pour se fondre dans l'encoche. Le thème colore le panneau ouvert. Si « Réduire les animations » est activé dans macOS, elles sont désactivées.")
        }
    }

    // MARK: - Général

    private var generalSection: some View {
        Section {
            Toggle("Lancer NookFlow à l'ouverture de session", isOn: Binding(
                get: { launchAtLogin.isOn },
                set: { launchAtLogin.setOn($0) }
            ))

            if launchAtLogin.needsApproval {
                HStack {
                    Text("macOS demande ton approbation.")
                        .foregroundStyle(.orange)
                    Button("Ouvrir les Réglages") { launchAtLogin.openSystemSettings() }
                }
                .font(.caption)
            }
            if let error = launchAtLogin.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Restaurer les paramètres par défaut…", role: .destructive) {
                confirmingReset = true
            }
            .confirmationDialog(
                "Restaurer les paramètres par défaut ?",
                isPresented: $confirmingReset
            ) {
                Button("Restaurer", role: .destructive) { preferences.resetToDefaults() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Widgets, ouverture, thème et animations reviennent à leur valeur d'origine. Tes notes, fichiers et le lancement à la connexion ne changent pas.")
            }
        } header: {
            Text("Général")
        } footer: {
            Text("NookFlow \(appVersion). Toutes les données restent sur ton Mac.")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
