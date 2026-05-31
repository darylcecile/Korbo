import SwiftUI

struct SessionsSidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(spacing: 16) {
                Image(systemName: "square.and.pencil")
                Image(systemName: "bubble.left.and.bubble.right")
                Image(systemName: "arrow.triangle.branch")
                Spacer()
                Image(systemName: "calendar")
                Image(systemName: "magnifyingglass")
                Image(systemName: "slider.horizontal.3")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("recent")
                    ForEach(SampleData.sessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            // Footer
            HStack(spacing: 18) {
                Image(systemName: "gearshape")
                Image(systemName: "questionmark.circle")
                Image(systemName: "info.circle")
                Spacer()
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.textTertiary)
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func sessionRow(_ session: SampleData.SessionRow) -> some View {
        let selected = app.selectedSessionID == session.id
        return Button {
            app.selectedSessionID = session.id
        } label: {
            HStack(spacing: 8) {
                Text(session.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                Spacer(minLength: 8)
                Text(session.relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Theme.panelRaised : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
