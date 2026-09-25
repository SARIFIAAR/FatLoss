import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Mirrors the local `AppData` to Firestore at `users/{uid}` (one JSON blob per user, used for sync) and
/// merges remote changes back in. The app is fully usable without signing in. `CloudMirror` additionally
/// writes flat per-day / per-meal rows plus a profile so the backend can trend every data point per user.
@Observable
final class CloudSync {
    private(set) var userID: String?
    private(set) var email: String?
    var status = "Not signed in"
    var lastError: String?
    var isSyncing = false

    private weak var store: Store?
    private weak var photoSync: PhotoSync?
    private var listener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var pushTask: Task<Void, Never>?
    private var currentNonce: String?
    private let mirror = CloudMirror()
    private var remoteHasProfile = false

    // MARK: Onboarding restore + collision (auth-first flow, build 52)

    /// State of the post-sign-in cloud fetch, so the onboarding "Welcome back / Restoring your plan"
    /// beat can bind to the ACTUAL Firestore round-trip (never a fake timer). Honest and observable:
    /// `.restoring` while the first snapshot is in flight, `.restored` once the plan is merged in,
    /// `.failed` on a network/auth error (the UI offers retry — it never falls through to the questionnaire).
    enum RestoreState: Equatable { case idle, restoring, restored, failed(String) }
    var restoreState: RestoreState = .idle

    /// True once we KNOW (from a real fetch) that the signed-in Apple ID already owns a cloud plan.
    /// This is the load-bearing branch signal for onboarding — NOT device state (fixes Bug 1: a new app
    /// version / reinstall no longer mistakes a returning user for a brand-new one).
    var accountHasCloudProfile = false

    /// Set when a GUEST who entered a questionnaire signs into an account that ALREADY has a cloud plan.
    /// The merge is held until the user chooses (Bug 2 fix). `nil` = no pending decision.
    var pendingCollision: PendingCollision?
    struct PendingCollision: Equatable { let remote: AppData; let local: AppData }

    /// True while an initial fetch is deciding the branch, so the onboarding can hold the sign-in screen
    /// (spinner on the Apple button) rather than flashing a wrong branch.
    var isResolvingSignIn = false

    private let deviceID: String = {
        let k = "cloud-device-id"
        if let id = UserDefaults.standard.string(forKey: k) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: k)
        return id
    }()

    var isConfigured: Bool { Self.didConfigure }
    var isSignedIn: Bool { userID != nil }

    private static var didConfigure = false

    static func configureFirebaseIfPossible() {
        guard !didConfigure,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        didConfigure = true
        FirebaseApp.configure()
        installBootstrap()
    }

    /// One-time-per-install cleanup for the reinstall gotcha: iOS preserves BOTH the Firebase Auth
    /// session and our Keychain isolation marker across app *deletion*, so a reinstall would silently
    /// auto-resume the last signed-in account (and, pre-fix, could adopt its residual local data). The
    /// `installBootstrapped` flag lives in UserDefaults, which IS cleared on uninstall (the Keychain is
    /// not) — so on the first launch of a fresh install we sign out once and clear the marker, forcing a
    /// clean login. Mirrors the SurgiMD build-63 AppDelegate bootstrap. Runs before the auth listener is
    /// attached (in `attach`), so this sign-out happens before any snapshot/merge could run.
    private static func installBootstrap() {
        let key = "installBootstrapped"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? Auth.auth().signOut()
        Keychain.delete(markerKey)
    }

    func attach(store: Store, photoSync: PhotoSync? = nil) {
        self.store = store
        self.photoSync = photoSync
        guard isConfigured else { status = "Cloud sync not configured"; return }
        store.onChange = { [weak self] in self?.schedulePush() }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.handleAuth(user) }
        }
    }

    /// Keychain key for the uid that owns the on-device `AppData`. ThisDeviceOnly so a backup/filesystem
    /// attacker can't edit it to force adoption of another account's residual data.
    private static let markerKey = "localDataOwnerUID"

    private func handleAuth(_ user: User?) {
        userID = user?.uid
        email = user?.email
        listener?.remove()
        listener = nil
        guard let user else {
            status = "Not signed in"
            accountHasCloudProfile = false
            restoreState = .idle
            pendingCollision = nil
            isResolvingSignIn = false
            photoSync?.stop()
            return
        }
        // Account isolation MUST run before the snapshot listener attaches / any merge happens, so a
        // different account never sees or re-uploads the previous user's local data. It returns true ONLY
        // when it ADOPTED guest (nil-marker) local answers into this account — the single case that can
        // collide with an existing cloud plan. A returning owner (marker == uid) is NOT a collision, so the
        // "use your saved plan?" prompt no longer fires on every launch (bug: it fired for signed-in users).
        pendingLocalGuestPlan = prepareForAccount(user.uid)
        // Start photo sync for this account AFTER isolation has run (cache is either kept for the same owner
        // or wiped for a different one), so the listener can only ever surface this uid's own photos.
        photoSync?.start(uid: user.uid)
        status = "Connecting…"
        restoreState = .restoring
        isResolvingSignIn = true
        listener = docRef(user.uid).addSnapshotListener { [weak self] snap, error in
            Task { @MainActor in self?.handleSnapshot(snap, error) }
        }
    }

    /// Whether the current sign-in carried guest answers that still survive after account isolation
    /// (i.e. this device adopted local-only data into the account). Read once in `handleSnapshot`.
    private var pendingLocalGuestPlan = false

    /// Enforce local-data account isolation for the account that just signed in.
    ///
    /// - marker == uid  → same owner: keep local data (offline edits sync up normally).
    /// - marker != uid  → a *different* account owns the on-device store: WIPE local to empty, clear the
    ///                    pending push + this account's mirror SHA cache, then stamp the new marker. After
    ///                    the wipe `store.snapshot()` is empty, so the `!snap.exists` seed path can only
    ///                    push an empty blob — no foreign data reaches `users/{newUid}`.
    /// - marker == nil  → fresh install / previously-unauthed local-only use: ADOPT the current local data
    ///                    for this uid (stamp the marker, no wipe) so offline Free users keep their data.
    /// Returns `true` ONLY when it adopted guest (nil-marker) local data that holds a plan — the single
    /// case that can collide with an existing cloud plan. Same-owner (marker == uid) and different-owner
    /// (wiped) both return `false`, so a returning signed-in user never sees the collision prompt.
    @discardableResult
    private func prepareForAccount(_ uid: String) -> Bool {
        let marker = Keychain.get(Self.markerKey)
        if marker == uid { return false }                 // same owner — keep local, NOT a collision
        if marker != nil {                                // different account owns the local store
            pushTask?.cancel()                            // drop any queued push of the previous user's data
            pushTask = nil
            remoteHasProfile = false
            store?.resetLocalData()                       // local is now empty
            mirror.clearCache(for: uid)                   // no stale row hashes for the incoming account
            Keychain.set(uid, for: Self.markerKey)
            return false                                  // local wiped — nothing to collide
        }
        // marker == nil → adopt this device's guest/local-only data for the account (no wipe).
        Keychain.set(uid, for: Self.markerKey)
        return (store?.data.intake != nil) || (store?.data.isEmpty == false)   // adopted a guest plan?
    }

    private func docRef(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    private func handleSnapshot(_ snap: DocumentSnapshot?, _ error: Error?) {
        if let error {
            lastError = error.localizedDescription
            status = "Sync error"
            // A returning user's restore round-trip failed — surface it so the UI can retry, and never
            // let the welcome-back beat fall through into a fresh questionnaire.
            if restoreState == .restoring { restoreState = .failed(error.localizedDescription) }
            isResolvingSignIn = false
            return
        }
        guard let snap, let store else { return }
        if !snap.exists {
            // First sign-in from this account: no cloud plan → this is a NEW account (run the questionnaire).
            remoteHasProfile = false
            accountHasCloudProfile = false
            pendingLocalGuestPlan = false
            isResolvingSignIn = false
            restoreState = .idle
            schedulePush(immediate: true)   // seed the cloud with local data (empty for a fresh sign-in)
            return
        }
        guard !snap.metadata.hasPendingWrites else { return }
        remoteHasProfile = snap.get("profile.createdAt") != nil
        // Older blobs (schema 1) have no per-day rows yet: back-fill them once.
        let needsMirror = (snap.get("schema") as? Int ?? 0) < CloudMirror.schema
        guard let json = snap.get("json") as? String,
              let raw = json.data(using: .utf8),
              let remote = try? Store.decoder.decode(AppData.self, from: raw) else {
            if restoreState == .restoring { restoreState = .failed("Couldn't read your saved plan.") }
            isResolvingSignIn = false
            return
        }

        let remoteHasPlan = remoteHasProfile || remote.intake != nil || !remote.isEmpty
        // Real, fetch-driven branch signal for onboarding (Bug 1 fix).
        accountHasCloudProfile = remoteHasPlan

        let local = store.snapshot()

        // Bug 2: a GUEST filled the questionnaire, then signed into an account that ALREADY has a plan.
        // Do NOT silently union-merge — pause and ask (default = cloud wins). Only for the first fetch
        // of this sign-in (`pendingLocalGuestPlan`), and only when both sides actually hold a plan.
        if pendingLocalGuestPlan, remoteHasPlan, (local.intake != nil || !local.isEmpty) {
            pendingLocalGuestPlan = false
            isResolvingSignIn = false
            restoreState = .restored          // remote plan is in hand; the confirm is a UI decision now
            pendingCollision = PendingCollision(remote: remote, local: local)
            lastError = nil
            status = "Choose which plan to keep"
            return                             // hold the merge until resolveCollision(...)
        }
        pendingLocalGuestPlan = false
        isResolvingSignIn = false

        let merged = local.merged(with: remote)
        if merged != local {
            print("CloudSync merge: local \(local.updatedAt)/settings \(local.settingsUpdatedAt) remote \(remote.updatedAt)/settings \(remote.settingsUpdatedAt) → program \(merged.program) reminders water=\(merged.reminders.waterOn) walk=\(merged.reminders.walkOn)")
            store.isApplyingRemote = true
            store.data = merged
            store.lastModified = merged.updatedAt
            store.settingsModified = merged.settingsUpdatedAt
            store.isApplyingRemote = false
        }
        if merged != remote || needsMirror { schedulePush() }
        lastError = nil
        status = "Synced " + Date().formatted(date: .omitted, time: .shortened)
        // The plan is now in hand — release the "Restoring your plan…" beat (returning-user branch).
        if restoreState == .restoring { restoreState = .restored }
    }

    /// Resolve the guest→existing-account collision (Bug 2). `useCloud` (default action) discards the
    /// just-entered guest answers and keeps the account's saved plan; `false` keeps what the user just
    /// entered and overwrites the cloud with it. Never a silent union merge.
    func resolveCollision(useCloud: Bool) {
        guard let pending = pendingCollision, let store else { return }
        pendingCollision = nil
        if useCloud {
            store.isApplyingRemote = true
            store.data = pending.remote
            store.lastModified = pending.remote.updatedAt
            store.settingsModified = pending.remote.settingsUpdatedAt
            store.isApplyingRemote = false
            status = "Restored your saved plan"
        } else {
            // Keep local: push it up so the cloud reflects the just-entered answers (local wins).
            schedulePush(immediate: true)
            status = "Kept your new answers"
        }
        restoreState = .restored
        lastError = nil
    }

    /// Debug only: present the collision confirm for screenshots (`-showCollision 1`).
    func debugPresentCollision() {
        pendingCollision = PendingCollision(remote: AppData(), local: AppData())
    }

    /// Retry the initial fetch after a restore failure (returning-user welcome-back beat).
    func retryRestore() {
        guard let uid = userID else { return }
        restoreState = .restoring
        isResolvingSignIn = true
        listener?.remove()
        listener = docRef(uid).addSnapshotListener { [weak self] snap, error in
            Task { @MainActor in self?.handleSnapshot(snap, error) }
        }
    }

    func schedulePush(immediate: Bool = false) {
        guard let uid = userID else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .seconds(2)) }
            guard !Task.isCancelled, let self, let store = self.store else { return }
            await self.push(uid: uid, data: store.snapshot())
        }
    }

    private func push(uid: String, data: AppData) async {
        guard let raw = try? Store.encoder.encode(data),
              let json = String(data: raw, encoding: .utf8) else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let user = Auth.auth().currentUser
            var fields: [String: Any] = [
                "json": json,
                "ownerUid": uid,                       // pin the writer == doc owner (defense-in-depth for rules)
                "updatedAt": Timestamp(date: data.updatedAt),
                "deviceId": deviceID,
                "schema": CloudMirror.schema,
            ]
            fields.merge(CloudMirror.profileFields(data: data, displayName: user?.displayName,
                                                   email: user?.email ?? email, isNew: !remoteHasProfile)) { _, new in new }
            try await docRef(uid).setData(fields, merge: true)
            remoteHasProfile = true
            try await mirror.push(uid: uid, data: data)
            lastError = nil
            status = "Synced " + Date().formatted(date: .omitted, time: .shortened)
        } catch {
            lastError = error.localizedDescription
            status = "Sync error"
        }
    }

    func syncNow() { schedulePush(immediate: true) }

    func signOut() {
        do { try Auth.auth().signOut() } catch { lastError = error.localizedDescription }
    }

    // MARK: Sign in with Apple (used by SwiftUI's SignInWithAppleButton)

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { lastError = error.localizedDescription }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                lastError = "Apple sign-in returned no identity token."
                return
            }
            let fbCred = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: cred.fullName)
            Task {
                do {
                    _ = try await Auth.auth().signIn(with: fbCred)
                    store?.showToast("Signed in — cloud sync on ☁️")
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
