import SwiftUI
import LocalAuthentication

/// Biometric app lock (E1-04). When enabled, HUMANS requires Face ID / Touch ID (or the device
/// passcode as fallback) to open, so health data stays private on a shared or lost phone.
/// Zero PHI leaves the device; this is purely a local gate using `LocalAuthentication`.
@Observable
final class AppLock {
    private let key = "appLockEnabled"

    /// Whether the user has turned the lock on. Persisted across launches.
    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: key) } }

    /// True while the lock screen should cover the app.
    var isLocked = false

    /// Set while the system biometric sheet is up, so scene-phase churn (the sheet briefly
    /// deactivates the app) doesn't re-lock or double-prompt mid-authentication.
    private var authenticating = false

    /// Debug/QA only (`-lockPreview 1`): hold the lock screen on-screen without auto-prompting,
    /// so the gate UI can be screenshotted on a simulator that has no enrolled biometrics.
    var previewMode = false

    init() {
        // Debug/QA (`-lockPreview 1`): force the branded gate on-screen without auto-prompting.
        // Read here (before the first LockView.onAppear) so preview wins the timing race.
        if UserDefaults.standard.bool(forKey: "lockPreview") {
            previewMode = true
            enabled = true
            isLocked = true
            return
        }
        let on = UserDefaults.standard.bool(forKey: key)
        enabled = on
        // Start locked when the feature is on, so a cold launch requires auth before anything shows.
        isLocked = on
    }

    /// Human label for the device's biometry ("Face ID" / "Touch ID") for copy.
    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "biometrics"
        }
    }

    /// SF Symbol matching the device biometry, for the unlock button / toggle.
    var biometrySymbol: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .touchID ? "touchid" : "faceid"
    }

    /// Can this device authenticate at all (biometrics OR a device passcode)? If neither is set
    /// we must never enable the lock — that would trap the user out of their own data.
    var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Lock the app as it leaves the foreground, if the feature is on.
    func lockOnBackground() {
        guard enabled, !authenticating else { return }
        isLocked = true
    }

    /// Prompt for biometrics / passcode and unlock on success. No-op if already unlocked or mid-prompt.
    func unlock() {
        guard isLocked, !authenticating else { return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No biometrics and no passcode — fail open rather than trap the user out.
            isLocked = false
            return
        }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock HUMANS") { [weak self] ok, _ in
            DispatchQueue.main.async {
                self?.authenticating = false
                if ok { self?.isLocked = false }
            }
        }
    }

    /// One-off biometric/passcode check for gating a sensitive surface (e.g. the document vault),
    /// independent of the app-lock setting. Calls back on the main thread. Fails open only when the
    /// device has no biometrics/passcode at all, so the user is never trapped out of their own data.
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            completion(true); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Toggle the feature. Turning ON requires one successful auth first (confirms the user can
    /// actually unlock) and is refused if the device has no biometrics/passcode.
    func setEnabled(_ on: Bool) {
        guard on else { enabled = false; isLocked = false; return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { enabled = false; return }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on app lock for HUMANS") { [weak self] ok, _ in
            DispatchQueue.main.async {
                self?.authenticating = false
                self?.enabled = ok
            }
        }
    }
}

/// Full-screen gate shown over the app while `AppLock.isLocked`. Auto-prompts on appear; the button
/// lets the user retry if they cancelled the system sheet.
struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("SplashMark")
                    .resizable().scaledToFit()
                    .frame(width: 84, height: 84)
                Text("HUMANS")
                    .font(Theme.titleL).foregroundStyle(Theme.text).kerning(3)
                Text("Locked").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Button { lock.unlock() } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: lock.biometrySymbol)
                }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 10)
            }
        }
        .onAppear { if !lock.previewMode { lock.unlock() } }
    }
}
