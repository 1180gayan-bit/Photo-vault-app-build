import Foundation
import LocalAuthentication

/// Decides whether the vault is locked, and handles the passcode,
/// Face ID / Touch ID, auto-lock and too-many-attempts lockout.
@MainActor
final class AuthManager: ObservableObject {
    enum State {
        case needsSetup
        case locked
        case unlocked
    }

    private enum Keys {
        static let hasLaunched = "hasLaunchedBefore"
        static let biometrics = "biometricsEnabled"
        static let autoLock = "autoLockSeconds"
        static let failedAttempts = "failedAttempts"
        static let lockoutEnds = "lockoutEnds"
    }

    /// Wrong guesses allowed before the keypad is paused.
    private static let freeAttempts = 5

    @Published private(set) var state: State
    @Published private(set) var lockoutEnds: Date?
    @Published var biometricsEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricsEnabled, forKey: Keys.biometrics) }
    }
    /// Seconds the app may stay in the background before it locks. 0 = lock immediately.
    @Published var autoLockDelay: Int {
        didSet { UserDefaults.standard.set(autoLockDelay, forKey: Keys.autoLock) }
    }

    private var backgroundedAt: Date?
    private var hasAutoPromptedBiometrics = false

    init() {
        let defaults = UserDefaults.standard
        // Keychain items survive deleting the app, but the vault files don't.
        // On a fresh install, clear any old passcode and key so the user starts clean.
        if !defaults.bool(forKey: Keys.hasLaunched) {
            Keychain.deleteAll()
            defaults.set(true, forKey: Keys.hasLaunched)
        }
        state = Passcode.isSet ? .locked : .needsSetup
        biometricsEnabled = defaults.object(forKey: Keys.biometrics) as? Bool ?? true
        autoLockDelay = defaults.integer(forKey: Keys.autoLock)
        if let ends = defaults.object(forKey: Keys.lockoutEnds) as? Date, ends > Date() {
            lockoutEnds = ends
        } else {
            lockoutEnds = nil
        }
    }

    // MARK: Biometrics

    var canUseBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Biometrics"
        @unknown default: return "Biometrics"
        }
    }

    var biometryIcon: String {
        switch biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock"
        @unknown default: return "lock"
        }
    }

    /// True when the lock screen should offer Face ID / Touch ID.
    var biometricsAvailable: Bool {
        biometricsEnabled && canUseBiometrics
    }

    func unlockWithBiometrics() async {
        guard state == .locked, biometricsAvailable else { return }
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"
        context.localizedFallbackTitle = ""
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your vault"
            )
            if success { didUnlock() }
        } catch {
            // Cancelled or failed: the passcode keypad stays on screen.
        }
    }

    /// Shows the Face ID prompt once each time the app locks, so cancelling it doesn't loop.
    func autoPromptBiometricsIfNeeded() async {
        guard state == .locked, !hasAutoPromptedBiometrics, !isLockedOut else { return }
        hasAutoPromptedBiometrics = true
        await unlockWithBiometrics()
    }

    // MARK: Passcode

    func createPasscode(_ code: String) throws {
        try Passcode.set(code)
        didUnlock()
    }

    func changePasscode(to code: String) throws {
        try Passcode.set(code)
    }

    func verifyPasscode(_ code: String) -> Bool {
        Passcode.verify(code)
    }

    /// Returns true if the passcode was right and the vault is now unlocked.
    func unlock(with code: String) -> Bool {
        guard state == .locked, !isLockedOut else { return false }
        if Passcode.verify(code) {
            didUnlock()
            return true
        }
        failedAttempts += 1
        if failedAttempts >= Self.freeAttempts {
            // 30s, then 1m, 2m, 4m... capped at one hour.
            let extra = failedAttempts - Self.freeAttempts
            let seconds = min(30 * pow(2, Double(min(extra, 10))), 3600)
            let ends = Date().addingTimeInterval(seconds)
            lockoutEnds = ends
            UserDefaults.standard.set(ends, forKey: Keys.lockoutEnds)
        }
        return false
    }

    var isLockedOut: Bool {
        lockoutRemaining(at: Date()) > 0
    }

    func lockoutRemaining(at date: Date) -> TimeInterval {
        guard let lockoutEnds else { return 0 }
        return max(0, lockoutEnds.timeIntervalSince(date))
    }

    var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: Keys.failedAttempts) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.failedAttempts) }
    }

    // MARK: Locking

    func lock() {
        guard state == .unlocked else { return }
        hasAutoPromptedBiometrics = false
        state = .locked
    }

    func sceneDidEnterBackground() {
        backgroundedAt = Date()
        if autoLockDelay == 0 { lock() }
    }

    func sceneDidBecomeActive() {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil
        if Date().timeIntervalSince(backgroundedAt) >= Double(autoLockDelay) {
            lock()
        }
    }

    private func didUnlock() {
        failedAttempts = 0
        lockoutEnds = nil
        UserDefaults.standard.removeObject(forKey: Keys.lockoutEnds)
        state = .unlocked
    }
}
