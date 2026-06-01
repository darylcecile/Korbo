import SwiftUI

/// Right-hand context panel: git · files · context. M1 wires the **context** tab
/// to live session token/cost data; git and files arrive in later milestones
/// (M3 / M5) and show honest "coming soon" states until then.
struct ContextPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().overlay(Theme.border)

            switch app.rightTab {
            case .git:
                GitPane()
            case .files:
                FilesPane()
            case .context:
                contextTab
            }
            Spacer(minLength: 0)
        }
        .background(Theme.panel)
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(AppModel.RightTab.allCases) { tab in
                Button { app.rightTab = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage).font(.system(size: 12))
                        Text(tab.title).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(app.rightTab == tab ? Theme.textPrimary : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Context tab (live)

    @ViewBuilder
    private var contextTab: some View {
        if let session = store.selectedSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metricRow("Cost", value: session.cost.map { String(format: "$%.4f", $0) } ?? "—")
                    if let usage = store.latestUsage {
                        usageSection(usage)
                    }
                    Divider().overlay(Theme.border)
                    metricRow("Additions", value: "+\(session.additions)", color: Theme.added)
                    metricRow("Deletions", value: "-\(session.deletions)", color: Theme.removed)
                    if let project = session.projectName {
                        metricRow("Project", value: project)
                    }
                    if let model = session.model?.modelID {
                        metricRow("Model", value: model)
                    }
                }
                .padding(16)
            }
        } else {
            comingSoon(icon: "doc.text.magnifyingglass",
                       title: "No session selected",
                       detail: "Select a session to see its token usage and cost.")
        }
    }

    // MARK: Token usage

    private struct UsageSegment: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    private func segments(_ u: OCMessage.Usage) -> [UsageSegment] {
        [
            UsageSegment(label: "Input", value: u.input ?? 0, color: Color(hex: 0x5B8DEF)),
            UsageSegment(label: "Cache", value: u.cacheTotal, color: Theme.textTertiary),
            UsageSegment(label: "Output", value: u.output ?? 0, color: Theme.added),
            UsageSegment(label: "Reasoning", value: u.reasoning ?? 0, color: Color(hex: 0xB07CD8))
        ].filter { $0.value > 0 }
    }

    @ViewBuilder
    private func usageSection(_ usage: OCMessage.Usage) -> some View {
        let total = usage.resolvedTotal
        let segs = segments(usage)
        let limit = store.contextLimit
        let fraction = limit.map { min(total / Double($0), 1) }
        let warn = (fraction ?? 0) >= 0.8

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Context usage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let limit {
                    Text("\(formatted(total)) / \(formatted(Double(limit)))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("\(formatted(total)) tokens")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Proportional breakdown bar (input / cache / output / reasoning).
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segs) { seg in
                        Rectangle()
                            .fill(seg.color)
                            .frame(width: max(2, geo.size.width * (seg.value / max(total, 1))))
                    }
                    if let fraction, fraction < 1 {
                        Rectangle().fill(Theme.panelRaised)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let fraction {
                HStack(spacing: 6) {
                    if warn {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.removed)
                    }
                    Text("\(Int((fraction * 100).rounded()))% of context window")
                        .font(.system(size: 11))
                        .foregroundStyle(warn ? Theme.removed : Theme.textSecondary)
                }
            }

            // Legend with per-bucket counts.
            VStack(spacing: 4) {
                ForEach(segs) { seg in
                    HStack(spacing: 8) {
                        Circle().fill(seg.color).frame(width: 8, height: 8)
                        Text(seg.label)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(formatted(seg.value))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }

    private func metricRow(_ label: String, value: String, color: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(color)
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value, value > 0 else { return "0" }
        return NumberFormatter.localizedString(from: NSNumber(value: Int(value)), number: .decimal)
    }

    private func comingSoon(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
