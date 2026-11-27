import AppIntents
import LensMonitorCore
import WidgetKit

/// Un modello con budget giornaliero, scelto in "Modifica widget".
struct ModelEntity: AppEntity {
    /// `provider/modello`.
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modello"
    static let defaultQuery = ModelQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

/// I modelli arrivano dalla lens a ogni apertura del menu: la lista segue LENS_MODEL_LIMITS.
struct ModelQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ModelEntity] {
        identifiers.map { ModelEntity(id: $0, name: Format.modelName($0)) }
    }

    func suggestedEntities() async throws -> [ModelEntity] {
        await WidgetModels.load(settings: WidgetSettings()).map { ModelEntity(id: $0.key, name: $0.name) }
    }
}

struct SelectModelIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Modello"
    static let description = IntentDescription("Il modello da seguire; senza scelta quello più vicino al budget.")

    @Parameter(title: "Modello")
    var model: ModelEntity?
}
