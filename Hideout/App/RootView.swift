import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch auth.state {
            case .needsSetup:
                PasscodeSetupView(purpose: .firstTime)
            case .locked:
                LockScreenView()
            case .unlocked:
                AlbumsView()
            }

            // Hides the vault in the app switcher and when Control Center is pulled down.
            if scenePhase != .active {
                PrivacyCoverView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                auth.sceneDidEnterBackground()
            case .active:
                auth.sceneDidBecomeActive()
            default:
                break
            }
        }
        .onChange(of: auth.state) { _, state in
            if state == .unlocked {
                vault.open()
            } else {
                vault.close()
            }
        }
    }
}

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial)
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Hideout")
                    .font(.title2.weight(.semibold))
            }
        }
        .ignoresSafeArea()
    }
}
