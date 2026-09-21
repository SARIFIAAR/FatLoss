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
    private var listener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var pushTask: Task<Void, Never>?
    private var currentNonce: String?
    private let mirror = CloudMirror()
    private var remoteHasProfile = false

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

    func attach(store: Store) {
        self.store = store
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
        guard let user else { status = "Not signed in"; return }
        // Account isolation MUST run before the snapshot listener attaches / any merge happens, so a
        // different account never sees or re-uploads the previous user's local data.
        prepareForAccount(user.uid)
        status = "Connecting…"
        listener = docRef(user.uid).addSnapshotListener { [weak self] snap, error in
            Task { @MainActor in self?.handleSnapshot(snap, error) }
        }
    }

    /// Enforce local-data account isolation for the account that just signed in.
    ///
    /// - marker == uid  → same owner: keep local data (offline edits sync up normally).
    /// - marker != uid  → a *different* account owns the on-device store: WIPE local to empty, clear the
    ///                    pending push + this account's mirror SHA cache, then stamp the new marker. After
    ///                    the wipe `store.snapshot()` is empty, so the `!snap.exists` seed path can only
    ///                    push an empty blob — no foreign data reaches `users/{newUid}`.
    /// - marker == nil  → fresh install / previously-unauthed local-only use: ADOPT the current local data
    ///                    for this uid (stamp the marker, no wipe) so offline Free users keep their data.
    private func prepareForAccount(_ uid: String) {
        let marker = Keychain.get(Self.markerKey)
        if marker == uid { return }                       // same owner — nothing to do
        if marker != nil {                                // different account owns the local store
            pushTask?.cancel()                            // drop any queued push of the previous user's data
            pushTask = nil
            remoteHasProfile = false
            store?.resetLocalData()                       // local is now empty
            mirror.clearCache(for: uid)                   // no stale row hashes for the incoming account
        }
        // marker == nil → adopt (fresh/local-only): fall through to stamp, no wipe.
        Keychain.set(uid, for: Self.markerKey)
    }

    private func docRef(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    private func handleSnapshot(_ snap: DocumentSnapshot?, _ error: Error?) {
        if let error { lastError = error.localizedDescription; status = "Sync error"; return }
        guard let snap, let store else { return }
        if !snap.exists {
            // First sign-in from this account: seed the cloud with local data.
            remoteHasProfile = false
            schedulePush(immediate: true)
            return
        }
        guard !snap.metadata.hasPendingWrites else { return }
        remoteHasProfile = snap.get("profile.createdAt") != nil
        // Older blobs (schema 1) have no per-day rows yet: back-fill them once.
        let needsMirror = (snap.get("schema") as? Int ?? 0) < CloudMirror.schema
        guard let json = snap.get("json") as? String,
              let raw = json.data(using: .utf8),
              let remote = try? Store.decoder.decode(AppData.self, from: raw) else { return }

        let local = store.snapshot()
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
