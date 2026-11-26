import AppKit

struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    /// Écran sans encoche : un simple « pill » centré en haut.
    static let fallback = NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 32)

    var compactSize: CGSize {
        hasNotch
            ? CGSize(width: notchWidth + 24, height: notchHeight)
            : CGSize(width: 180, height: notchHeight)
    }

    /// Taille compacte avec un « badge » (par exemple le minuteur) : le panneau dépasse de chaque
    /// côté de l'encoche pour faire de la place à une icône à gauche et au temps à droite.
    func compactSize(withBadge: Bool) -> CGSize {
        guard withBadge else { return compactSize }
        return hasNotch
            ? CGSize(width: notchWidth + 132, height: notchHeight)
            : CGSize(width: 180, height: notchHeight)
    }

    var expandedSize: CGSize {
        CGSize(width: 580, height: notchHeight + 210)
    }
}

enum ScreenGeometry {
    /// Préfère l'écran qui a une encoche (l'écran intégré du MacBook), sinon l'écran principal.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func geometry(for screen: NSScreen) -> NotchGeometry {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0 else { return .fallback }

        var width: CGFloat = 200 // valeur de secours si les zones auxiliaires sont indisponibles
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
        }
        return NotchGeometry(hasNotch: true, notchWidth: width, notchHeight: topInset)
    }

    /// Rectangle de la fenêtre : centré horizontalement, collé en haut de l'écran.
    static func frame(size: CGSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
