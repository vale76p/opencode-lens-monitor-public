import LensMonitorCore
import SwiftUI

/// Il colore SwiftUI di pannello e widget; quello AppKit dell'etichetta nella barra è
/// StatusColor+NSColor.swift, solo nell'app.
extension StatusColor {
    var color: Color {
        switch self {
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .gray: .secondary
        case .warning: .yellow
        }
    }
}
