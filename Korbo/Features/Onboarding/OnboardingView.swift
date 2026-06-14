import SwiftUI

/// First-run onboarding: a short paged carousel that introduces Korbo and ends
/// on a Connect step (Korbo Cloud vs self-hosted). Presented as a full-screen
/// cover on first launch and re-showable from Settings. Completion is persisted
/// by `AppModel`, so it never reappears unasked.
struct OnboardingView: View {
    @EnvironmentObject private var app: AppModel
    @State private var page = 0

    private let pages: [Intro] = [
        Intro(art: .mark,
              title: "Welcome to Korbo",
              body: "Glad you’re here. Let’s get you set up — it only takes a minute, then you can build from anywhere."),
        Intro(art: .symbol("rectangle.split.3x1"),
              title: "Your whole workspace",
              body: "Sessions, conversation, and git · files · context in one familiar three-pane layout, made for touch and the Apple Pencil."),
        Intro(art: .symbol("lock.shield"),
              title: "You stay in control",
              body: "Korbo doesn’t run the agent. opencode runs on a server you control — Korbo connects over a secure link and drives it.")
    ]

    /// The connect step is appended after the intro pages, so it is the last tab.
    private var connectIndex: Int { pages.count }
    private var isConnectPage: Bool { page == connectIndex }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                    .readableColumn()
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        introView(pages[i]).tag(i)
                    }
                    connectView.tag(connectIndex)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                bottomBar
                    .readableColumn()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.18), .clear],
                           center: .top, startRadius: 0, endRadius: 540)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Skip") { app.finishOnboarding(opening: nil) }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .opacity(isConnectPage ? 0 : 1)
                .disabled(isConnectPage)
                .animation(.easeInOut(duration: 0.2), value: isConnectPage)
        }
        .frame(height: 44)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        VStack(spacing: 22) {
            dots
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { page = min(page + 1, connectIndex) }
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Self.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .opacity(isConnectPage ? 0 : 1)
            .disabled(isConnectPage)
            .allowsHitTesting(!isConnectPage)
        }
        .padding(.bottom, 28)
        .animation(.easeInOut(duration: 0.2), value: isConnectPage)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0...connectIndex, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Theme.accent : Theme.border)
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: page)
            }
        }
    }

    // MARK: - Intro pages

    @ViewBuilder
    private func introView(_ p: Intro) -> some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            art(p.art)
            VStack(spacing: 14) {
                Text(p.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(p.body)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .readableColumn()
    }

    @ViewBuilder
    private func art(_ art: Art) -> some View {
        switch art {
        case .mark:
            Image("KorboMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 136, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 31, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
        case .symbol(let name):
            ZStack {
                RoundedRectangle(cornerRadius: 31, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 31, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                    .frame(width: 136, height: 136)
                Image(systemName: name)
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    // MARK: - Connect step

    private var connectView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Text("Let’s connect")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Choose where opencode runs. You can change this anytime in Settings.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                connectCard(icon: "cloud.fill",
                            title: "Korbo Cloud",
                            subtitle: "Run opencode on a managed instance — no setup required.",
                            prominent: true) { app.finishOnboarding(opening: .cloud) }
                connectCard(icon: "server.rack",
                            title: "Connect your own server",
                            subtitle: "Point Korbo at an opencode endpoint you host.",
                            prominent: false) { app.finishOnboarding(opening: .selfHosted) }
            }
            Button("I’ll do this later") { app.finishOnboarding(opening: nil) }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .readableColumn()
    }

    private func connectCard(icon: String,
                             title: String,
                             subtitle: String,
                             prominent: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(prominent ? Self.onAccent : Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(prominent ? Self.onAccent : Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(prominent ? Self.onAccent.opacity(0.75) : Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(prominent ? Self.onAccent.opacity(0.5) : Theme.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? Theme.accent : Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Foreground colour for content sitting on the accent fill. The accent
    /// palette is uniformly light-to-mid, so a near-black reads well on every one.
    private static let onAccent = Color(hex: 0x111114)

    // MARK: - Model

    private struct Intro {
        let art: Art
        let title: String
        let body: String
    }

    private enum Art {
        case mark
        case symbol(String)
    }
}

private extension View {
    /// Caps content to a readable column and centres it, with a gutter on narrow
    /// screens. Applied to page *content* — not the paging `TabView` — so the
    /// carousel stays full-bleed and pages slide off the screen edges instead of
    /// being clipped at a mid-screen boundary.
    func readableColumn() -> some View {
        self
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
    }
}
