import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var spaceUsed = "…"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if auth.canUseBiometrics {
                        Toggle("Unlock with \(auth.biometryName)", isOn: $auth.biometricsEnabled)
                    }
                    Picker("Auto-Lock", selection: $auth.autoLockDelay) {
                        Text("Immediately").tag(0)
                        Text("After 1 minute").tag(60)
                        Text("After 5 minutes").tag(300)
                    }
                    NavigationLink("Change Passcode") {
                        ChangePasscodeScreen()
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Hideout locks when you leave the app. After 5 wrong passcodes, the keypad pauses for a while, and the wait gets longer with each wrong try.")
                }

                Section {
                    LabeledContent("Albums", value: "\(vault.albums.count)")
                    LabeledContent("Photos", value: "\(vault.photoCount)")
                    LabeledContent("Videos", value: "\(vault.videoCount)")
                    LabeledContent("Space Used", value: spaceUsed)
                } header: {
                    Text("Vault")
                } footer: {
                    Text("Everything is encrypted and stored only on this iPhone. Nothing is uploaded to the internet, and the vault is left out of iCloud and computer backups. If you delete Hideout, everything in it is deleted too, so save anything you want to keep back to Photos first.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let bytes = await vault.bytesUsed()
                spaceUsed = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
        }
    }
}

private struct ChangePasscodeScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PasscodeSetupView(purpose: .change) {
            dismiss()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
