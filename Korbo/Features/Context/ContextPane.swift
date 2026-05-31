import SwiftUI

struct ContextPane: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab strip
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
            Divider().overlay(Theme.border)

            switch app.rightTab {
            case .git: gitTab
            case .files: placeholder("Files tree, editor & manual-save toggle")
            case .context: placeholder("Context items & token usage breakdown")
            }
            Spacer(minLength: 0)
        }
        .background(Theme.panel)
    }

    private var gitTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 12))
                    Text("main").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                    Image(systemName: "house")
                }
                .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 8) {
                    pill("commit", filled: true)
                    pill("update")
                    pill("pr")
                    Spacer()
                    pill("sync")
                }

                HStack {
                    Text("Changes").font(.system(size: 14, weight: .semibold))
                    Text("\(SampleData.changes.count)/\(SampleData.changes.count)")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text("revert all").font(.system(size: 12)).foregroundStyle(Theme.removed)
                }

                VStack(spacing: 6) {
                    ForEach(SampleData.changes) { change in
                        changeRow(change)
                    }
                }
            }
            .padding(16)
        }
    }

    private func changeRow(_ c: SampleData.ChangeRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.accent).font(.system(size: 13))
            Text(c.status).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary).frame(width: 12)
            Text((c.path as NSString).lastPathComponent)
                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text("+\(c.added)").font(.system(size: 11)).foregroundStyle(Theme.added)
            Text("-\(c.removed)").font(.system(size: 11)).foregroundStyle(Theme.removed)
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private func pill(_ text: String, filled: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(filled ? Theme.panelRaised : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: filled ? 0 : 1))
            .foregroundStyle(Theme.textSecondary)
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Image(systemName: "hammer").font(.system(size: 28)).foregroundStyle(Theme.textTertiary)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity).padding(24)
    }
}
