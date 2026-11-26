# NookFlow

![CI](https://github.com/Miahy-rhn/NookFlow/actions/workflows/ci.yml/badge.svg)

Application macOS native (Swift / SwiftUI / AppKit), inspirée de NotchNook : un panneau flottant
noir collé à l'encoche du MacBook (ou une pilule en haut de l'écran sans encoche) qui s'ouvre au
survol, avec des widgets : étagère de fichiers, notes, minuteur, calendrier, Spotify.

Aucune donnée n'est envoyée sur Internet : tout reste en local. L'app ne modifie pas l'encoche
physique, elle dessine un panneau par-dessus.

## Installation (utilisateurs)

1. Télécharge `NookFlow-x.y.zip` dans la section **Releases** du dépôt GitHub et dézippe-le.
2. Glisse `NookFlow.app` dans `/Applications`.
3. Premier lancement : l'app n'est pas notarisée par Apple, donc macOS la bloque.
   - Ouvre **Réglages Système > Confidentialité et sécurité**, descends jusqu'au message
     « NookFlow a été bloqué », clique **Ouvrir quand même**, puis confirme.
   - Ou, dans le Terminal : `xattr -dr com.apple.quarantine /Applications/NookFlow.app`
4. Accepte les autorisations quand elles apparaissent (Calendrier, Notifications, Automatisation
   de Spotify). Chacune est facultative et ne sert qu'au widget concerné.

Compatibilité : macOS 14 ou plus, Apple Silicon et Intel.

Alternative sans blocage : compiler soi-même (voir ci-dessous), une app compilée sur sa propre
machine n'est pas mise en quarantaine.

## Prérequis

- macOS 14 ou plus (testé visé : macOS 26.2)
- Xcode installé (pas seulement les Command Line Tools)
- Homebrew

## Lancer le projet

```bash
brew install xcodegen
cd NookFlow            # le dossier qui contient project.yml
xcodegen generate      # crée NookFlow.xcodeproj
open NookFlow.xcodeproj
```

Dans Xcode : choisis la cible **NookFlow** et la destination **My Mac**, puis ⌘R.

Si Xcode demande une équipe de signature : Signing & Capabilities > « Sign to Run Locally »
(ou ton Apple ID personnel).

Si `xcodebuild` se plaint de l'outil sélectionné :

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Structure

```
project.yml                 configuration XcodeGen (agent sans Dock, sans sandbox, macOS 14)
NookFlow/
├── App/      NookFlowApp.swift, AppDelegate.swift
├── Window/   NotchPanel.swift, NotchPanelController.swift, ScreenGeometry.swift
├── State/    NotchState.swift, AppContext.swift, AppPreferences.swift
├── Views/    NotchRootView.swift, ExpandedView.swift, SettingsView.swift, ...
├── Services/ NotificationService.swift, LaunchAtLogin.swift
└── Widgets/
    ├── NookWidget.swift (protocole des widgets + registre), BuiltInWidgets.swift (les cinq widgets)
    ├── Files/  FileShelfStore.swift, FilesWidgetView.swift
    ├── Notes/  NotesStore.swift, NotesWidgetView.swift
    ├── Calendar/ CalendarService.swift, CalendarModel.swift, CalendarWidgetView.swift
    ├── Music/  SpotifyBridge.swift, NowPlayingModel.swift, MusicWidgetView.swift
    └── Timer/  TimerModel.swift, TimerWidgetView.swift
```

`NookFlow/Info.plist` est généré par XcodeGen au moment de `xcodegen generate`.

## Ajouter un widget

1. Ajouter un cas à `WidgetID` (`State/NotchState.swift`) : titre, icône, et couleurs d'ambiance dans `Views/WidgetBackdrop.swift`.
2. Écrire une classe qui adopte `NookWidget` (`Widgets/BuiltInWidgets.swift`) : sa vue, et si besoin le clavier, le rafraîchissement à l'ouverture.
3. L'ajouter à la liste du registre dans `State/AppContext.swift`.

## Ce qu'on doit observer

1. Une icône dans la barre de menus, aucune icône dans le Dock.
2. Une forme noire arrondie collée à l'encoche.
3. Survol ou clic : le panneau s'agrandit ; en quittant la zone, il se réduit après ~0,5 s.
4. Menu de l'icône : afficher/masquer, ouvrir/réduire, quitter.

## Tests

⌘U dans Xcode lance les 82 tests de la cible `NookFlowTests` (logique du minuteur, des notes,
des fichiers, du calendrier, de la musique et des préférences).

## Vérifier le projet

```bash
./scripts/check.sh          # régénère le projet et vérifie qu'aucun fichier Swift n'est oublié
./scripts/check.sh --test   # idem + lance les tests
```

La même commande tourne automatiquement sur GitHub (onglet **Actions**) à chaque push.

## Installer pour l'utiliser au quotidien

```bash
./scripts/install.sh
```

Le script génère le projet, compile en Release, copie `NookFlow.app` dans `/Applications` et la lance.
Ferme d'abord la version lancée depuis Xcode (⌘.), sinon deux NookFlow tournent en même temps.

Signature : l'app est signée « en local » (identité ad hoc). Elle fonctionne sur ce Mac, mais macOS
peut redemander les autorisations (Calendrier, Automatisation de Spotify, Notifications) après chaque
nouvelle compilation, car la signature change. Pour les éviter, il faut un certificat stable
(compte Apple Developer gratuit pour un certificat de développement, ou payant pour distribuer).

## Fabriquer une archive à partager

```bash
./scripts/package.sh 1.0     # crée dist/NookFlow-1.0.zip (Apple Silicon + Intel)
```

Cette archive est signée « ad hoc » : elle fonctionne mais déclenche l'avertissement Gatekeeper
décrit plus haut. Pour une distribution sans avertissement, il faut un compte Apple Developer
payant (99 $/an), un certificat « Developer ID Application », le Hardened Runtime (avec
l'entitlement `com.apple.security.automation.apple-events` pour piloter Spotify), puis la
notarisation (`xcrun notarytool submit`) et l'agrafage (`xcrun stapler staple`).

## Licence

MIT, voir `LICENSE`.
