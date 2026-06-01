import ActivityKit
import WidgetKit
import SwiftUI

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
    static let korboAccent = Color(hex: 0xE8783C)
    static let korboText = Color(hex: 0xEDEDEF)
    static let korboTextDim = Color(hex: 0x9A9AA2)
    static let korboBG = Color(hex: 0x141417)
}

/// Lock-screen + Dynamic Island presentation for a running Korbo agent turn.
/// On iPad only the lock-screen banner appears (no Dynamic Island hardware);
/// on iPhone the compact/expanded/minimal Dynamic Island variants are used too.
struct KorboRunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KorboRunAttributes.self) { context in
            lockScreen(context)
                .padding(16)
                .activityBackgroundTint(Color.korboBG)
                .activitySystemActionForegroundColor(Color.korboAccent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: glyph(context))
                        .foregroundStyle(Color.korboAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isActive {
                        Text(timerInterval: context.attributes.startedAt...Date.distantFuture,
                             countsDown: false)
                            .monospacedDigit()
                            .frame(width: 54)
                            .foregroundStyle(Color.korboTextDim)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.sessionTitle)
                            .font(.caption).bold()
                            .lineLimit(1)
                            .foregroundStyle(Color.korboText)
                        Text(context.state.status)
                            .font(.caption2)
                            .foregroundStyle(Color.korboTextDim)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let tokens = context.state.tokens {
                        Text("\(compactTokens(tokens)) tokens")
                            .font(.caption2)
                            .foregroundStyle(Color.korboTextDim)
                    }
                }
            } compactLeading: {
                Image(systemName: glyph(context))
                    .foregroundStyle(Color.korboAccent)
            } compactTrailing: {
                if context.state.isActive {
                    Text(timerInterval: context.attributes.startedAt...Date.distantFuture,
                         countsDown: false)
                        .monospacedDigit()
                        .frame(width: 44)
                        .foregroundStyle(Color.korboTextDim)
                }
            } minimal: {
                Image(systemName: glyph(context))
                    .foregroundStyle(Color.korboAccent)
            }
            .widgetURL(URL(string: "korbo://session"))
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<KorboRunAttributes>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.korboAccent.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: glyph(context))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.korboAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.sessionTitle)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                    .foregroundStyle(Color.korboText)
                HStack(spacing: 6) {
                    Text(context.state.status)
                        .foregroundStyle(Color.korboTextDim)
                    if let tokens = context.state.tokens {
                        Text("· \(compactTokens(tokens)) tok")
                            .foregroundStyle(Color.korboTextDim)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 8)
            if context.state.isActive {
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture,
                     countsDown: false)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.korboTextDim)
            } else {
                Image(systemName: context.state.status == "Failed"
                      ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(context.state.status == "Failed"
                                     ? Color(hex: 0xD15B5B) : Color(hex: 0x4CAF7D))
            }
        }
    }

    private func glyph(_ context: ActivityViewContext<KorboRunAttributes>) -> String {
        switch context.state.status {
        case "Needs permission": return "lock.shield"
        case "Has a question": return "questionmark.bubble"
        case "Failed": return "exclamationmark.triangle"
        case "Finished": return "checkmark.seal"
        default: return "sparkles"
        }
    }

    private func compactTokens(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fk", Double(n) / 1000) }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }
}
