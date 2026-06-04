import SwiftUI

/// Account section for Korbo Cloud. Renders the signed-out call-to-action (web
/// sign-in plus a pasted-token fallback) or, once authenticated, the account
/// summary: identity, credit balance, top-up, refresh, and sign-out.
///
/// This is a self-contained, `Section`-emitting view designed to be dropped
/// into a parent dashboard's `Form`/`List`. It intentionally owns no navigation
/// chrome — the embedding screen supplies it. Reads the shared ``CloudStore``
/// from the environment (`RootEnvironment.cloud`).
struct CloudAccountView: View {
    @EnvironmentObject private var cloud: CloudStore
    @Environment(\.openURL) private var openURL

    /// Local fallback token, used only on the signed-out paste path.
    @State private var pastedToken: String = ""
    @State private var showPasteToken = false

    /// Top-up amounts (in credits) offered by the "Buy credits" menu.
    private let topupAmounts = [1000, 5000, 10000]

    var body: some View {
        Group {
            if cloud.isSignedIn {
                signedInSections
            } else {
                signedOutSection
            }
            errorSection
        }
    }

    // MARK: - Signed out

    @ViewBuilder
    private var signedOutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect your Korbo Cloud account to run opencode in the cloud.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 2)

            Button {
                Task { await cloud.signIn() }
            } label: {
                HStack {
                    Label("Sign in with GitHub", systemImage: "arrow.right.circle")
                    if cloud.isBusy {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(cloud.isBusy)

            DisclosureGroup(isExpanded: $showPasteToken) {
                SecureField("Korbo Cloud token", text: $pastedToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))

                Button("Use token") {
                    let token = pastedToken
                    Task { await cloud.signIn(pastedToken: token) }
                }
                .disabled(cloud.isBusy || pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("One‑tap sign in requires the Korbo Cloud backend's native redirect; until then, sign in at my.korbo.app in Safari and paste the token here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            } label: {
                Text("Paste token instead")
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Korbo Cloud")
        } footer: {
            Text("Sign in with GitHub to provision cloud instances and run opencode remotely.")
        }
    }

    // MARK: - Signed in

    @ViewBuilder
    private var signedInSections: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(accountTitle)
                            .foregroundStyle(Theme.textPrimary)
                        if cloud.me?.isAdmin == true {
                            adminBadge
                        }
                    }
                    if let email = cloud.me?.email, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
            }
        } header: {
            Text("Korbo Cloud")
        }

        Section {
            if let balance = cloud.balance {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(balance.available) credits available")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("balance \(balance.balance) · reserved \(balance.reserved)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 2)
            } else {
                Text("Balance unavailable.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Menu {
                ForEach(topupAmounts, id: \.self) { amount in
                    Button("\(amount) credits") { buyCredits(amount) }
                }
            } label: {
                Label("Buy credits", systemImage: "creditcard")
            }
            .disabled(cloud.isBusy)
        } header: {
            Text("Balance")
        }

        Section {
            Button {
                Task { await cloud.refreshMe() }
            } label: {
                HStack {
                    Label("Refresh", systemImage: "arrow.clockwise")
                    if cloud.isBusy {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(cloud.isBusy)

            Button(role: .destructive) {
                Task { await cloud.signOut() }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(cloud.isBusy)
        }
    }

    private var adminBadge: some View {
        Text("Admin")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.accent.opacity(0.18))
            )
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error = cloud.lastError, !error.isEmpty {
            Section {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.removed)
            }
        }
    }

    // MARK: - Helpers

    /// Display name for the signed-in account, preferring the GitHub login.
    private var accountTitle: String {
        if let login = cloud.me?.githubLogin, !login.isEmpty {
            return "@" + login
        }
        return cloud.me?.id ?? "Korbo Cloud account"
    }

    private func buyCredits(_ amount: Int) {
        Task {
            if let url = try? await cloud.topupURL(credits: amount) {
                openURL(url)
            }
        }
    }
}
