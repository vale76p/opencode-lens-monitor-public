import AppKit
import LensMonitorCore

/// Il pallino dell'etichetta nella barra si disegna con AppKit (MenuBarIcon): solo l'app ne ha
/// bisogno, il widget usa `color` in Shared/StatusColor+Color.swift.
extension StatusColor {
    var nsColor: NSColor {
        switch self {
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        case .gray: .tertiaryLabelColor
        case .warning: .systemYellow
        }
    }
}
