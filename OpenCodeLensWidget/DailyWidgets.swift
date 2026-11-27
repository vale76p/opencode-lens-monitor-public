import LensMonitorCore
import SwiftUI
import WidgetKit

@main
struct OpenCodeLensWidgets: WidgetBundle {
    var body: some Widget {
        ModelWidget()
        SummaryWidget()
    }
}

/// Piccolo: l'anello; medio: l'andamento. Il kind è per compatibilità: cambiarlo toglie i widget già piazzati.
struct ModelWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "local.opencode-lens-monitor.usage", intent: SelectModelIntent.self, provider: ModelProvider()) { entry in
            DailyWidgetView(entry: entry)
        }
        .configurationDisplayName("Modello oggi")
        .description("Token di oggi di un modello contro il suo budget giornaliero; nel medio, ora per ora dal reset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Il kind è per compatibilità: cambiarlo toglie i widget già piazzati.
struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "local.opencode-lens-monitor.models", provider: SummaryProvider()) { entry in
            DailyWidgetView(entry: entry)
        }
        .configurationDisplayName("Modelli oggi")
        .description("Token di oggi dei modelli contro il loro budget giornaliero.")
        .supportedFamilies([.systemMedium])
    }
}

struct DayEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
    /// Ogni 15 minuti, o subito dopo il reset del giorno.
    let nextUpdate: Date

    static func sample(_ kind: WidgetContent.Kind) -> DayEntry {
        let now = BudgetReport.sample.now
        return DayEntry(date: now, content: .sample(kind), nextUpdate: now.addingTimeInterval(WidgetContent.refreshInterval))
    }

    static func load(_ kind: WidgetContent.Kind, model: String?, now: Date) async -> DayEntry {
        let loaded = await WidgetContent.load(kind, model: model, now: now, settings: WidgetSettings())
        return DayEntry(date: now, content: loaded.content, nextUpdate: loaded.nextUpdate)
    }

    /// Stessi dati, una voce per minuto: solo il tempo al reset cambia fino al prossimo aggiornamento.
    var timeline: Timeline<DayEntry> {
        let entries = WidgetContent.entryDates(from: date, until: nextUpdate).map { DayEntry(date: $0, content: content, nextUpdate: nextUpdate) }
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }
}

/// Widget piccolo e medio: il modello scelto in "Modifica widget".
struct ModelProvider: AppIntentTimelineProvider {
    private func kind(_ context: Context) -> WidgetContent.Kind {
        context.family == .systemMedium ? .trend : .ring
    }

    func placeholder(in context: Context) -> DayEntry { .sample(kind(context)) }

    func snapshot(for configuration: SelectModelIntent, in context: Context) async -> DayEntry {
        if context.isPreview { return .sample(kind(context)) }
        return await .load(kind(context), model: configuration.model?.id, now: .now)
    }

    /// L'app forza il reload quando i dati cambiano.
    func timeline(for configuration: SelectModelIntent, in context: Context) async -> Timeline<DayEntry> {
        await DayEntry.load(kind(context), model: configuration.model?.id, now: .now).timeline
    }
}

/// Le closure di WidgetKit non sono Sendable: le si passa al Task così.
private struct Completion<T>: @unchecked Sendable {
    let call: (T) -> Void
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { .sample(.summary) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        if context.isPreview { return completion(.sample(.summary)) }
        let done = Completion(call: completion)
        Task { done.call(await DayEntry.load(.summary, model: nil, now: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let done = Completion(call: completion)
        Task { done.call(await DayEntry.load(.summary, model: nil, now: .now).timeline) }
    }
}
