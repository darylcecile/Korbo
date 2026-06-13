import SwiftUI

/// Korbo Cloud management surface, presented as a sheet from the connection
/// flow. Composes the account/sign-in section and the provisioned-instances
/// list (built as independent, embeddable sections). Once a cloud instance is
/// connected the sheet dismisses itself so the user lands back in the workspace.
struct CloudDashboardView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @EnvironmentObject private var cloud: CloudStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                CloudAccountView()
                if cloud.isSignedIn {
                    Section {
                        CloudInstancesView()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        CloudSessionsView()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Korbo Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: store.status) { _, status in
            // A successful connection to a cloud instance drops the user back to
            // the workspace.
            if status.isConnected { dismiss() }
        }
    }
}
