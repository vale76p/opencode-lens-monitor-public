import Foundation

/// Voci del menu di accensione in fondo al pannello: la decisione (quale azione sul servizio,
/// se abilitata) sta qui, testabile; la vista fa solo il popUp del menu AppKit.
public enum PowerMenu {
    public enum Action: Equatable, Sendable {
        case start, stop, quit
    }

    public struct Item: Equatable, Sendable {
        public let title: String
        public let enabled: Bool
        public let action: Action

        public init(title: String, enabled: Bool, action: Action) {
            self.title = title
            self.enabled = enabled
            self.action = action
        }

        /// Esci dal Monitor sta sotto un separatore, staccato dall'azione sul servizio.
        public var separatorBefore: Bool { action == .quit }
    }

    /// `primaryAction` è quella del modello (`MonitorModel.primaryAction`), `nil` con una lens di
    /// sviluppo o senza servizio: allora resta solo Esci. Durante Avvia/Ferma l'azione è spenta.
    public static func items(primaryAction: ServiceAction?, busy: Bool) -> [Item] {
        var items: [Item] = []
        switch primaryAction {
        case .start: items.append(Item(title: "Avvia lens", enabled: !busy, action: .start))
        case .stop: items.append(Item(title: "Ferma lens", enabled: !busy, action: .stop))
        case nil: break
        }
        items.append(Item(title: "Esci dal Monitor", enabled: true, action: .quit))
        return items
    }
}
