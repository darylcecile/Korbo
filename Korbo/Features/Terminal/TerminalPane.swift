import SwiftUI
import UIKit
import SwiftTerm

/// Terminal tab: live pseudo-terminals served by opencode's PTY API. Each running
/// PTY is a tab; the active one is rendered by a SwiftTerm `TerminalView` wired to
/// the `/pty/{id}/connect` WebSocket for real-time I/O. REST handles spawn/kill/
/// resize; the live byte stream is owned by `TerminalHostView` below.
struct TerminalPane: View {
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            content
        }
        .background(Theme.panel)
        .task { await store.loadTerminal() }
    }

    // MARK: Header (tabs + actions)

    private var header: some View {
        HStack(spacing: 8) {
            if store.ptys.isEmpty {
                Text("Terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.ptys) { pty in
                            tab(for: pty)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            newButton
            if store.activePtyID != nil {
                Button {
                    if let id = store.activePtyID { Task { await store.killPty(id) } }
                } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                        .foregroundStyle(Theme.removed)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func tab(for pty: OCPty) -> some View {
        let active = pty.id == store.activePtyID
        return Button { store.activePtyID = pty.id } label: {
            HStack(spacing: 5) {
                Image(systemName: "terminal").font(.system(size: 10))
                Text(tabTitle(pty)).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? Theme.panelRaised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func tabTitle(_ pty: OCPty) -> String {
        let base = (pty.command as NSString).lastPathComponent
        return base.isEmpty ? pty.title : base
    }

    @ViewBuilder
    private var newButton: some View {
        if store.shells.isEmpty {
            Button { Task { await store.newPty() } } label: {
                Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button("Default shell") { Task { await store.newPty() } }
                Divider()
                ForEach(store.shells.filter(\.acceptable)) { shell in
                    Button(shell.name) { Task { await store.newPty(command: shell.path) } }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !store.status.isConnected {
            empty(icon: "bolt.horizontal.circle",
                  title: "Not connected",
                  detail: "Connect to an opencode server to open a terminal.")
        } else if let id = store.activePtyID,
                  let client = store.activeClient,
                  let url = client.ptyWebSocketURL(id) {
            TerminalHostView(
                ptyID: id,
                url: url,
                headers: client.socketHeaders(),
                onResize: { cols, rows in
                    Task { await store.resizePty(id, rows: rows, cols: cols) }
                },
                onError: { message in store.reportTerminalError(message) }
            )
            .id(id)
            .ignoresSafeArea(.container, edges: .bottom)
        } else {
            empty(icon: "terminal",
                  title: "No terminal",
                  detail: "Start a shell session to run commands on the server.") {
                Button {
                    Task { await store.newPty() }
                } label: {
                    Text("New terminal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func empty(icon: String, title: String, detail: String,
                       @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            action()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SwiftTerm host

/// Bridges a SwiftTerm `TerminalView` to an opencode PTY WebSocket. The view owns
/// the live `PtyConnection`; output bytes are fed into the emulator and keystrokes
/// (and terminal resizes) flow back to the server.
struct TerminalHostView: UIViewRepresentable {
    let ptyID: String
    let url: URL
    let headers: [String: String]
    let onResize: (Int, Int) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResize: onResize, onError: onError)
    }

    func makeUIView(context: Context) -> TerminalView {
        let term = TerminalView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        term.terminalDelegate = context.coordinator
        term.nativeForegroundColor = UIColor(Theme.textPrimary)
        term.nativeBackgroundColor = UIColor(Theme.bg)
        term.backgroundColor = UIColor(Theme.bg)
        context.coordinator.attach(terminal: term, url: url, headers: headers)
        return term
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        private var connection: PtyConnection?
        private weak var terminal: TerminalView?
        private let onResize: (Int, Int) -> Void
        private let onError: (String) -> Void

        init(onResize: @escaping (Int, Int) -> Void, onError: @escaping (String) -> Void) {
            self.onResize = onResize
            self.onError = onError
        }

        func attach(terminal: TerminalView, url: URL, headers: [String: String]) {
            self.terminal = terminal
            let conn = PtyConnection(url: url, headers: headers)
            conn.onOutput = { [weak terminal] bytes in terminal?.feed(byteArray: bytes) }
            conn.onError = { [weak self] message in self?.onError(message) }
            connection = conn
            conn.connect()
        }

        func detach() {
            connection?.close()
            connection = nil
        }

        // MARK: TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            connection?.send(data)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
