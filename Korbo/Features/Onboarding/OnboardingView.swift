import SwiftUI

/// First-run onboarding: a short paged carousel that introduces Korbo, lets the
/// user sign in to Korbo Cloud with GitHub, and ends on a Connect step (managed
/// cloud · your own server · a machine you run via the korbo CLI). Presented as a
/// full-screen cover on first launch and re-showable from Settings. Completion is
/// persisted by `AppModel`, so it never reappears unasked.
struct OnboardingView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var cloud: CloudStore
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

    /// Step layout: intro pages, then a GitHub sign-in step, then the connect
    /// step — appended in that order so they are the last two tabs.
    private var signInIndex: Int { pages.count }
    private var connectIndex: Int { pages.count + 1 }
    private var isIntroPage: Bool { page < signInIndex }

    /// BYO sessions (registered via the korbo CLI) that are reachable right now.
    private var onlineSessions: [CloudSession] { cloud.sessions.filter { $0.status.isOnline } }
    private var hasOnlineSession: Bool { !onlineSessions.isEmpty }

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
                    signInView.tag(signInIndex)
                    connectView.tag(connectIndex)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)
                .onChange(of: page) { newPage in
                    if newPage == connectIndex && cloud.isSignedIn {
                        Task { await cloud.refreshSessions() }
                    }
                }

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
                .opacity(isIntroPage ? 1 : 0)
                .disabled(!isIntroPage)
                .animation(.easeInOut(duration: 0.2), value: isIntroPage)
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
            .opacity(isIntroPage ? 1 : 0)
            .disabled(!isIntroPage)
            .allowsHitTesting(isIntroPage)
        }
        .padding(.bottom, 28)
        .animation(.easeInOut(duration: 0.2), value: isIntroPage)
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

    // MARK: - Sign-in step

    /// GitHub sign-in for Korbo Cloud. Optional: signing in unlocks managed cloud
    /// machines and any sessions the user runs via the korbo CLI, but a self-hosted
    /// user can skip straight to the connect step.
    private var signInView: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            art(.symbol(cloud.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle"))
            VStack(spacing: 14) {
                Text(cloud.isSignedIn ? "You’re signed in" : "Sign in with GitHub")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(signInBody)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 14) {
                if cloud.isSignedIn {
                    accentCapsuleButton("Continue") { goToConnect() }
                } else {
                    accentCapsuleButton("Continue with GitHub", busy: cloud.isBusy) {
                        Task {
                            await cloud.signIn()
                            if cloud.isSignedIn { goToConnect() }
                        }
                    }
                    Button("Skip for now") { goToConnect() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .disabled(cloud.isBusy)
                }
                if let error = cloud.lastError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.removed)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .readableColumn()
    }

    private var signInBody: String {
        if let login = cloud.me?.githubLogin, !login.isEmpty {
            return "Signed in as @\(login). Choose how you’d like to connect next."
        }
        return "Sign in to launch managed cloud machines or connect a machine you run yourself with the korbo CLI. Prefer your own server? You can skip this."
    }

    /// Shared accent “pill” button for the primary sign-in actions. Mirrors the
    /// Continue button in `bottomBar`, with an inline spinner while busy.
    private func accentCapsuleButton(_ title: String,
                                     busy: Bool = false,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Self.onAccent)
                    .opacity(busy ? 0 : 1)
                if busy {
                    ProgressView().tint(Self.onAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func goToConnect() {
        withAnimation(.easeInOut(duration: 0.25)) { page = connectIndex }
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
                            subtitle: "Run opencode on a managed machine — nothing to set up.",
                            prominent: true) { app.finishOnboarding(opening: .cloud) }
                connectCard(icon: "server.rack",
                            title: "Connect your own server",
                            subtitle: "Point Korbo at an opencode endpoint you host.",
                            prominent: false) { app.finishOnboarding(opening: .selfHosted) }
                if hasOnlineSession {
                    connectCard(icon: "desktopcomputer",
                                title: "A machine you’re running",
                                subtitle: byoSubtitle,
                                prominent: false) { connectToOwnMachine() }
                }
            }
            connectFooter
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .readableColumn()
    }

    /// Sign-in status hint plus the always-available “later” escape hatch.
    @ViewBuilder
    private var connectFooter: some View {
        VStack(spacing: 12) {
            if cloud.isSignedIn, let login = cloud.me?.githubLogin, !login.isEmpty {
                Label("Signed in as @\(login)", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            } else if !cloud.isSignedIn {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { page = signInIndex }
                } label: {
                    Label("Sign in with GitHub for cloud machines", systemImage: "arrow.right.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            Button("I’ll do this later") { app.finishOnboarding(opening: nil) }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 2)
    }

    private var byoSubtitle: String {
        if onlineSessions.count == 1 {
            return "Connect to “\(onlineSessions[0].displayName)”, online via the korbo CLI."
        }
        return "Connect to one of \(onlineSessions.count) machines online via the korbo CLI."
    }

    /// Connect a BYO machine. With a single online session, connect straight to it
    /// and dismiss; with several, hand off to the cloud dashboard to choose.
    private func connectToOwnMachine() {
        if onlineSessions.count == 1 {
            let session = onlineSessions[0]
            Task { await cloud.connectToSession(session) }
            app.finishOnboarding(opening: nil)
        } else {
            app.finishOnboarding(opening: .cloud)
        }
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
