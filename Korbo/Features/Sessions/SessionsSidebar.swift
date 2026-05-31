import SwiftUI

struct SessionsSidebar: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            content
            Spacer(minLength: 0)
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Button {
                Task { await store.createSession() }
            } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain)
                .disabled(!store.status.isConnected)
            Image(systemName: "bubble.left.and.bubble.right")
            Image(systemName: "arrow.triangle.branch")
            Spacer()
            Button {
                Task { await store.reloadSessions() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .disabled(!store.status.isConnected)
            Image(systemName: "magnifyingglass")
            Image(systemName: "slider.horizontal.3")
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.status {
        case .connected where store.sessions.isEmpty:
            emptyState(icon: "tray", title: "No sessions yet",
                       subtitle: "Start one with the compose button above.")
        case .connected:
            sessionList
        case .connecting:
            emptyState(icon: "arrow.triangle.2.circlepath", title: "Connecting…",
                       subtitle: store.servers.selectedServer?.normalizedURLString ?? "")
        case .failed(let message):
            disconnectedState(message: message)
        case .disconnected:
            disconnectedState(message: nil)
        }
    }

    private var sessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sectionHeader("recent")
                ForEach(store.sessions) { session in
                    sessionRow(session)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
    }

    private func sessionRow(_ session: OCSession) -> some View {
        let selected = store.selectedSessionID == session.id
        return Button {
            Task { await store.selectSession(session.id) }
        } label: {
            HStack(spacing: 8) {
                Text(session.title ?? "Untitled session")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                Spacer(minLength: 8)
                Text(RelativeTime.short(session.lastActivity))
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

    // MARK: States

    private func disconnectedState(message: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text("Not connected")
                .font(.system(size: 14, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                app.showConnectionSheet = true
            } label: {
                Text("Configure connection")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.18)))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 14, weight: .semibold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 18) {
            Button {
                app.showConnectionSheet = true
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Image(systemName: "gearshape")
                }
            }
            .buttonStyle(.plain)
            Image(systemName: "questionmark.circle")
            Image(systemName: "info.circle")
            Spacer()
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.textTertiary)
        .padding(16)
    }

    private var statusColor: Color {
        switch store.status {
        case .connected: return Theme.added
        case .connecting: return Theme.accent
        case .failed: return Theme.removed
        case .disconnected: return Theme.textTertiary
        }
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
}
