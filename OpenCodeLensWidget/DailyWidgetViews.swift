import Charts
import LensMonitorCore
import SwiftUI
import WidgetKit

struct DailyWidgetView: View {
    let entry: DayEntry

    var body: some View {
        Group {
            switch entry.content {
            case .model(let day, nil):
                RingView(day: day, now: entry.date)
            case .model(let day, let trend?):
                TrendView(day: day, trend: trend, now: entry.date)
            case .summary(let summary):
                SummaryView(summary: summary, now: entry.date)
            case .message(let text):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.secondary)
                    Text(text).font(.caption).multilineTextAlignment(.center)
                    Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "opencode-lens-monitor://dashboard"))
    }
}

extension ModelDay {
    /// Senza budget grigio esplicito: .secondary in Swift Charts diventa il colore d'accento.
    var tint: Color { pace == .noLimit ? .gray : pace.color.color }
}

struct RingView: View {
    let day: ModelDay
    let now: Date

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: day.progress ?? 0)
                    .stroke(day.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(day.percent ?? day.used)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 14)
            }
            .frame(width: 92, height: 92)
            VStack(spacing: 0) {
                Text(day.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(day.resetLine(at: now)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

struct TrendView: View {
    let day: ModelDay
    let trend: DayTrend
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(day.tint).frame(width: 10, height: 10)
                Text(day.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(day.percent ?? day.used).font(.title2.weight(.semibold)).monospacedDigit()
                if let badge = day.pace.badge {
                    PaceBadge(text: badge, color: day.tint)
                }
            }
            Chart {
                ForEach(trend.points) { point in
                    AreaMark(x: .value("Ora", point.hour), y: .value("Token", point.value))
                        .foregroundStyle(LinearGradient(colors: [day.tint.opacity(0.35), day.tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Ora", point.hour), y: .value("Token", point.value))
                        .foregroundStyle(day.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                if let average = trend.average {
                    RuleMark(y: .value("Ritmo", average))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: 0...Double(trend.hours))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: trend.ticks.map(\.hour)) { value in
                    AxisValueLabel { Text(label(at: value.as(Double.self))) }
                }
            }
            Text(day.resetLine(at: now)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func label(at hour: Double?) -> String {
        trend.ticks.first { $0.hour == hour }?.label ?? ""
    }
}

struct SummaryView: View {
    let summary: DaySummary
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Modelli").font(.headline)
                Spacer()
                Text("oggi").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(summary.rows) { SummaryRow(model: $0) }
            Spacer(minLength: 0)
            Text(summary.resetLine(at: now)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// Una riga per modello: nome, barra con la percentuale sopra, token usati su budget.
struct SummaryRow: View {
    let model: PanelState.ModelRow

    var body: some View {
        HStack(spacing: 8) {
            Text(model.name).font(.caption).lineLimit(1).truncationMode(.middle)
                .frame(width: 96, alignment: .leading)
            if let progress = model.progress {
                UsageBar(progress: progress, percent: model.percent ?? "", color: model.pace.color.color)
                Text(model.budget ?? "").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).frame(width: 68, alignment: .trailing)
            } else {
                Text(model.note ?? "senza budget").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Barra dell'uso con la percentuale scritta dentro: riempimento attenuato perché il testo resti
/// leggibile anche dove la barra è piena.
struct UsageBar: View {
    let progress: Double
    let percent: String
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(color.opacity(0.15))
            GeometryReader { geometry in
                Capsule().fill(color.opacity(0.55))
                    .frame(width: max(geometry.size.height, geometry.size.width * progress))
            }
            Text(percent).font(.caption2.weight(.semibold)).monospacedDigit()
                .padding(.leading, 6)
        }
        .frame(height: 15)
    }
}
