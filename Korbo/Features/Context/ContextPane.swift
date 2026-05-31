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
                comingSoon(icon: "folder",
                           title: "File explorer",
                           detail: "Browse and edit the workspace with a manual-save toggle — coming soon.")
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
                    if let tokens = session.tokens {
                        metricRow("Input tokens", value: formatted(tokens.input))
                        metricRow("Output tokens", value: formatted(tokens.output))
                        metricRow("Reasoning tokens", value: formatted(tokens.reasoning))
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
