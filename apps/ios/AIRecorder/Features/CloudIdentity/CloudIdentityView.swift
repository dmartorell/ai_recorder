import SwiftUI

struct CloudIdentityView: View {
    let coordinator: CloudIdentityCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                if let identity = coordinator.identity {
                    Section("Cloud backup") {
                        LabeledContent("Signed in as", value: identity.email)
                        Button("Sign out", role: .destructive) {
                            Task { await coordinator.signOut() }
                        }
                    }
                } else {
                    Section("Cloud backup") {
                        Text("Sign in to prepare this iPhone for private cloud backup. Recording and local Audio remain available offline.")
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        Button("Send magic link") {
                            Task { await coordinator.requestMagicLink(email: email.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.state == .requestingMagicLink)
                    }
                }

                if coordinator.state == .magicLinkSent {
                    Section { Text("Check your email and open the magic link to finish signing in.") }
                }
                if coordinator.state == .accountMismatch {
                    Section { Text("This iPhone’s local Audio library is already bound to another cloud account.").foregroundStyle(.red) }
                }
                if let error = coordinator.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Cloud backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await coordinator.restoreSession() }
        }
    }
}
