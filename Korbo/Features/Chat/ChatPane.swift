import SwiftUI

struct ChatPane: View {
    @EnvironmentObject private var app: AppModel
    @State private var draft: String = ""

    private var session: SampleData.SessionRow? {
        SampleData.sessions.first { $0.id == app.selectedSessionID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            messages
            composer
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Model / agent selector pill
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12))
                Text("Auto-discover").font(.system(size: 13))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelRaised))

            VStack(alignment: .leading, spacing: 2) {
                Text(session?.title ?? "New session")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(session?.project ?? "Korbo")
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                    Text(session?.branch ?? "main")
                    Text("+\(session?.added ?? 0)").foregroundStyle(Theme.added)
                    Text("-\(session?.removed ?? 0)").foregroundStyle(Theme.removed)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer()

            Text("13.6%").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.left.forwardslash.chevron.right")
            Button { app.showRightSidebar.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            Circle().fill(Theme.accent).frame(width: 26, height: 26)
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var messages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                userBubble("Provide a short report on what we've done here")
                assistantBlock()
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 14))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelRaised))
        }
    }

    private func assistantBlock() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(Theme.accent)
                Text("GPT-5.5").font(.system(size: 13, weight: .semibold))
                badge("build", Theme.added)
                badge("low", Color(hex: 0x5B8FD1))
            }
            Text("Implemented a file editor save-mode toggle.")
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 6) {
                bullet("Added persistent autosave/manual-save preference.")
                bullet("Manual save disables autosave and shows a save button when dirty.")
                bullet("Added a toolbar toggle after the save icon / Saved label.")
            }
            HStack(spacing: 16) {
                Label("3.3s", systemImage: "timer")
                Text("21:47")
            }
            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("–").foregroundStyle(Theme.textTertiary)
            Text(text).font(.system(size: 14))
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            VStack(alignment: .leading, spacing: 10) {
                TextField("@ for files/agents;  / for commands;  ! for shell", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...6)
                HStack(spacing: 14) {
                    Image(systemName: "plus.circle")
                    Image(systemName: "paperclip")
                    Spacer()
                    Text("low").foregroundStyle(Color(hex: 0x5B8FD1))
                    Text("GPT-5.5")
                    Text("Build").foregroundStyle(Theme.added)
                    Image(systemName: "paperplane.fill").foregroundStyle(Theme.accent)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .background(Theme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(16)
        }
    }
}
