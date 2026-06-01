import Foundation

/// Live bridge to a single opencode PTY over `GET /pty/{id}/connect` (a WebSocket).
///
/// Wire protocol (confirmed empirically against opencode):
/// - **server → client**: `text` frames carry raw terminal output (ANSI/UTF-8);
///   `binary` frames are control messages framed as a `0x00` opcode byte followed
///   by JSON (e.g. `{"cursor":221}`) — not terminal output, so they're ignored.
/// - **client → server**: raw stdin is written as `text` frames. Binary frames are
///   reserved for control, so keystrokes must go out as text.
///
/// Not actor-isolated: SwiftTerm's delegate calls `send` synchronously on the main
/// thread, while `URLSessionWebSocketTask` callbacks arrive on a background queue.
/// `onOutput`/`onError` are always delivered on the main queue so they can drive
/// the terminal view and SwiftUI state directly.
final class PtyConnection {
    private let url: URL
    private let headers: [String: String]
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var isClosed = false

    /// Raw terminal output bytes to feed into the emulator (main queue).
    var onOutput: ((ArraySlice<UInt8>) -> Void)?
    /// Connection-level error, e.g. handshake failure or drop (main queue).
    var onError: ((String) -> Void)?

    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = .infinity
        self.session = URLSession(configuration: cfg)
    }

    func connect() {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive()
    }

    /// Write raw stdin bytes to the host as a text frame.
    func send(_ bytes: ArraySlice<UInt8>) {
        guard let task, !isClosed else { return }
        let text = String(decoding: bytes, as: UTF8.self)
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            self?.deliverError(error.localizedDescription)
        }
    }

    func close() {
        isClosed = true
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receive() {
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self, !self.isClosed else { return }
            switch result {
            case .failure(let error):
                self.deliverError(error.localizedDescription)
            case .success(let message):
                self.deliverOutput(from: message)
                self.receive()
            }
        }
    }

    private func deliverOutput(from message: URLSessionWebSocketTask.Message) {
        let bytes: [UInt8]
        switch message {
        case .string(let text):
            bytes = Array(text.utf8)
        case .data(let data):
            // Binary frames are control messages (0x00 + JSON); ignore them.
            if data.first == 0x00 { return }
            bytes = Array(data)
        @unknown default:
            return
        }
        DispatchQueue.main.async { [weak self] in self?.onOutput?(bytes[...]) }
    }

    private func deliverError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.onError?(message)
        }
    }
}
