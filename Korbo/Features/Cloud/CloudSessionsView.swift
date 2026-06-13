import SwiftUI

/// Korbo "Your machines" section. Lists the account's self-hosted
/// (bring-your-own-machine) opencode sessions registered via the `korbo` CLI and
/// lets the user connect to the online ones.
///
/// These are distinct from managed cloud instances: they run on the user's own
/// hardware, are free (no credits), and carry a simple online/offline status
/// rather than a provisioning lifecycle. Like `CloudInstancesView`, this is a
/// self-contained `View` meant to embed inside the dashboard's `Form`/`ScrollView`.
struct CloudSessionsView: View {
    @EnvironmentObject private var cloud: CloudStore

    @State private var pendingRemove: CloudSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if cloud.isSignedIn {
                header
                sessionList
            } else {
                signedOutPlaceholder
            }
        }
        .task { if cloud.isSignedIn { await cloud.refreshSessions() } }
        .alert(
            "Remove machine?",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            presenting: pendingRemove
        ) { session in
            Button("Remove", role: .destructive) { remove(session) }
            Button("Cancel", role: .cancel) { pendingRemove = nil }
        } message: { session in
            Text("This removes “\(session.displayName)” from your account. You can re-add it by running the korbo CLI on that machine.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Your machines")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                Task { await cloud.refreshSessions() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .disabled(cloud.isBusy)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var sessionList: some View {
        if cloud.sessions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 10) {
                ForEach(cloud.sessions) { session in
                    SessionRow(session: session) { pendingRemove = session }
                        .environmentObject(cloud)
                }
            }
        }
    }

    /// Onboarding hint shown when the account has no self-hosted sessions yet.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No self-hosted machines yet.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text("Run the korbo CLI on your own machine to host a free opencode session and it'll show up here.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var signedOutPlaceholder: some View {
        Text("Sign in to see your self-hosted machines.")
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func remove(_ session: CloudSession) {
        pendingRemove = nil
        Task {
            try? await cloud.deleteSession(session.id)
            await cloud.refreshSessions()
        }
    }
}

// MARK: - Session row

/// A single self-hosted session card: identity, a "Local" badge, an online/offline
/// indicator, optional repo, and a Connect action that's disabled (with a clear
/// hint) while the machine is offline. No credit/cost UI — these sessions are free.
private struct SessionRow: View {
    @EnvironmentObject private var cloud: CloudStore

    let session: CloudSession
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topLine
            metaLine
            if let repo = session.repo, !repo.isEmpty {
                Label(repo, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !isOnline {
                Label("This machine is offline. Start it with the korbo CLI to connect.", systemImage: "bolt.slash")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionRow
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var topLine: some View {
        HStack(spacing: 8) {
            Text(session.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            localBadge
            Spacer(minLength: 8)
            statusPill
        }
    }

    /// Marks the session as self-hosted so it's never confused with a billed
    /// managed instance.
    private var localBadge: some View {
        Text("Local")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.accent.opacity(0.15)))
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isOnline ? Theme.added : Theme.textTertiary)
                .frame(width: 7, height: 7)
            Text(session.status.displayLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isOnline ? Theme.added : Theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill((isOnline ? Theme.added : Theme.textTertiary).opacity(0.15)))
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(session.id)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let created = session.createdAt {
                Text("·").foregroundStyle(Theme.textTertiary)
                Text(RelativeTime.short(created))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var actionRow: some View {
        Button {
            Task { await cloud.connectToSession(session) }
        } label: {
            Text("Connect")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(canConnect ? Color.white : Theme.textTertiary)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(canConnect ? Theme.accent : Theme.panelRaised)
        )
        .disabled(!canConnect)
    }

    // MARK: Derived

    private var isOnline: Bool { session.status.isOnline }
    private var canConnect: Bool { isOnline && !cloud.isBusy }
}
