import AppKit
import LensMonitorCore
import SwiftUI

/// Etichetta nella barra: logo, pallino e percentuale in un'unica immagine.
/// Non è template, altrimenti la barra toglierebbe il colore al pallino; logo e testo usano
/// `labelColor`, risolto a ogni disegno con l'aspetto corrente della barra.
struct MenuBarLabel: View {
    let panel: PanelState
    let service: ServiceState

    var body: some View {
        Image(nsImage: MenuBarIcon.image(dot: panel.dot, text: panel.menuBarText))
            .accessibilityLabel(service.statusText + (panel.menuBarText.isEmpty ? "" : ", oggi \(panel.menuBarText)"))
    }
}

enum MenuBarIcon {
    static func image(dot: StatusColor, text: String) -> NSImage {
        let textWidth = text.isEmpty ? 0 : ceil((text as NSString).size(withAttributes: attributes()).width) + 4
        let image = NSImage(size: NSSize(width: 14 + 4 + 8 + textWidth, height: 16), flipped: false) { _ in
            drawMark(in: NSRect(x: 0, y: 1, width: 14, height: 14))
            drawDot(dot, in: NSRect(x: 18, y: 4, width: 8, height: 8))
            if !text.isEmpty {
                let attributes = attributes()
                let height = (text as NSString).size(withAttributes: attributes).height
                (text as NSString).draw(at: NSPoint(x: 30, y: (16 - height) / 2), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func attributes() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: NSColor.labelColor]
    }

    /// Marchio stilizzato di OpenCode: quadrato cavo con un blocco pieno nella metà bassa.
    /// Stessa geometria di OpenCodeMark (SwiftUI, nel pannello), in AppKit perché l'etichetta della
    /// barra è un'unica NSImage: un ritocco va fatto in entrambi.
    static func drawMark(in rect: NSRect) {
        NSColor.labelColor.set()
        let outer = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        outer.lineWidth = 2
        outer.stroke()
        NSBezierPath(rect: NSRect(x: rect.minX + 4, y: rect.minY + 4, width: rect.width - 8, height: rect.height / 2 - 4)).fill()
    }

    static func drawDot(_ dot: StatusColor, in rect: NSRect) {
        if dot == .warning,
           let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(paletteColors: [.systemYellow])) {
            symbol.draw(in: rect.insetBy(dx: -2, dy: -2))
            return
        }
        dot.nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}
