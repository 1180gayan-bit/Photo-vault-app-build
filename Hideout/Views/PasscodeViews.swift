import SwiftUI

/// A six-dot passcode field with a number pad.
struct PasscodeEntryView: View {
    let title: String
    var message: String? = nil
    var isError = false
    var disabled = false
    /// Increase this to make the dots shake (e.g. after a wrong passcode).
    var shakeCount = 0
    var biometryIcon: String? = nil
    var onBiometry: () -> Void = {}
    let onComplete: (String) -> Void

    @State private var code = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3.weight(.semibold))
            PasscodeDots(filled: code.count)
                .modifier(Shake(animatableData: CGFloat(shakeCount)))
                .animation(.default, value: shakeCount)
            Text(message ?? " ")
                .font(.footnote)
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 40, alignment: .top)
                .padding(.horizontal)
            Spacer(minLength: 10)
            PasscodeKeypad(
                biometryIcon: biometryIcon,
                onBiometry: onBiometry,
                onDigit: add,
                onDelete: { if !code.isEmpty { code.removeLast() } }
            )
            .disabled(disabled)
            .opacity(disabled ? 0.35 : 1)
            Spacer(minLength: 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func add(_ digit: Int) {
        guard !disabled, code.count < Passcode.length else { return }
        code.append(String(digit))
        if code.count == Passcode.length {
            let entered = code
            // Let the last dot fill in before reacting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                code = ""
                onComplete(entered)
            }
        }
    }
}

struct PasscodeDots: View {
    let filled: Int

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<Passcode.length, id: \.self) { index in
                Circle()
                    .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5)
                    .background(Circle().fill(index < filled ? Color.primary : Color.clear))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(filled) of \(Passcode.length) digits entered")
    }
}

struct PasscodeKeypad: View {
    var biometryIcon: String?
    var onBiometry: () -> Void
    var onDigit: (Int) -> Void
    var onDelete: () -> Void

    private let rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 26) {
                    ForEach(row, id: \.self) { digitKey($0) }
                }
            }
            HStack(spacing: 26) {
                if let biometryIcon {
                    KeyButton(action: onBiometry) {
                        Image(systemName: biometryIcon).font(.title)
                    }
                    .accessibilityLabel("Unlock with biometrics")
                } else {
                    Color.clear.frame(width: 76, height: 76)
                }
                digitKey(0)
                KeyButton(action: onDelete) {
                    Image(systemName: "delete.left").font(.title2)
                }
                .accessibilityLabel("Delete")
            }
        }
    }

    private func digitKey(_ digit: Int) -> some View {
        KeyButton(filled: true, action: { onDigit(digit) }) {
            Text("\(digit)").font(.system(size: 32, weight: .regular, design: .rounded))
        }
    }
}

private struct KeyButton<Label: View>: View {
    var filled = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 76, height: 76)
                .background(Circle().fill(filled ? Color.primary.opacity(0.08) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

// MARK: - Lock screen

struct LockScreenView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var wrongCount = 0
    @State private var message: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = auth.lockoutRemaining(at: context.date)
            PasscodeEntryView(
                title: "Enter Passcode",
                message: remaining > 0 ? "Too many wrong attempts. Try again in \(Self.format(remaining))." : message,
                isError: remaining > 0 || message != nil,
                disabled: remaining > 0,
                shakeCount: wrongCount,
                biometryIcon: auth.biometricsAvailable ? auth.biometryIcon : nil,
                onBiometry: { Task { await auth.unlockWithBiometrics() } },
                onComplete: { code in
                    if !auth.unlock(with: code) {
                        wrongCount += 1
                        message = "Wrong passcode. Try again."
                    }
                }
            )
        }
        .task {
            if scenePhase == .active { await auth.autoPromptBiometricsIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await auth.autoPromptBiometricsIfNeeded() }
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return total >= 60 ? "\(total / 60)m \(total % 60)s" : "\(total)s"
    }
}

// MARK: - Create / change passcode

struct PasscodeSetupView: View {
    enum Purpose {
        case firstTime
        case change
    }

    private enum Step {
        case verifyCurrent
        case enterNew
        case confirm(String)
    }

    let purpose: Purpose
    var onFinished: () -> Void = {}

    @EnvironmentObject private var auth: AuthManager
    @State private var step: Step
    @State private var errorMessage: String?
    @State private var shakeCount = 0

    init(purpose: Purpose, onFinished: @escaping () -> Void = {}) {
        self.purpose = purpose
        self.onFinished = onFinished
        _step = State(initialValue: purpose == .change ? .verifyCurrent : .enterNew)
    }

    var body: some View {
        PasscodeEntryView(
            title: title,
            message: errorMessage ?? hint,
            isError: errorMessage != nil,
            shakeCount: shakeCount,
            onComplete: handle
        )
    }

    private var title: String {
        switch step {
        case .verifyCurrent: return "Enter Current Passcode"
        case .enterNew: return purpose == .firstTime ? "Create a Passcode" : "Enter New Passcode"
        case .confirm: return "Confirm Passcode"
        }
    }

    private var hint: String? {
        switch step {
        case .enterNew where purpose == .firstTime:
            return "Choose 6 digits to lock Hideout. Use something different from your iPhone passcode, and don't forget it: it can't be recovered."
        case .confirm:
            return "Enter the same 6 digits again."
        default:
            return nil
        }
    }

    private func handle(_ code: String) {
        switch step {
        case .verifyCurrent:
            if auth.verifyPasscode(code) {
                errorMessage = nil
                step = .enterNew
            } else {
                fail("Wrong passcode. Try again.")
            }
        case .enterNew:
            errorMessage = nil
            step = .confirm(code)
        case .confirm(let first):
            guard code == first else {
                step = .enterNew
                fail("Those didn't match. Start again.")
                return
            }
            do {
                if purpose == .firstTime {
                    try auth.createPasscode(code)
                } else {
                    try auth.changePasscode(to: code)
                }
                onFinished()
            } catch {
                fail("Couldn't save the passcode: \(error.localizedDescription)")
            }
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        shakeCount += 1
    }
}
