import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Mirrors the local `AppData` to Firestore at `users/{uid}` (one JSON blob per user) and
/// merges remote changes back in. The app is fully usable without signing in.
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
    }

    func attach(store: Store) {
        self.store = store
        guard isConfigured else { status = "Cloud sync not configured"; return }
        store.onChange = { [weak self] in self?.schedulePush() }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.handleAuth(user) }
        }
    }

    private func handleAuth(_ user: User?) {
        userID = user?.uid
        email = user?.email
        listener?.remove()
        listener = nil
        guard let user else { status = "Not signed in"; return }
        status = "Connecting…"
        listener = docRef(user.uid).addSnapshotListener { [weak self] snap, error in
            Task { @MainActor in self?.handleSnapshot(snap, error) }
        }
    }

    private func docRef(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    private func handleSnapshot(_ snap: DocumentSnapshot?, _ error: Error?) {
        if let error { lastError = error.localizedDescription; status = "Sync error"; return }
        guard let snap, let store else { return }
        if !snap.exists {
            // First sign-in from this account: seed the cloud with local data.
            schedulePush(immediate: true)
            return
        }
        guard !snap.metadata.hasPendingWrites else { return }
        guard let json = snap.get("json") as? String,
              let raw = json.data(using: .utf8),
              let remote = try? Store.decoder.decode(AppData.self, from: raw) else { return }

        let merged = store.data.merged(with: remote)
        if merged != store.data {
            store.isApplyingRemote = true
            store.data = merged
            store.isApplyingRemote = false
        }
        if merged != remote { schedulePush() }
        lastError = nil
        status = "Synced " + Date().formatted(date: .omitted, time: .shortened)
    }

    func schedulePush(immediate: Bool = false) {
        guard let uid = userID else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .seconds(2)) }
            guard !Task.isCancelled, let self, let store = self.store else { return }
            await self.push(uid: uid, data: store.data)
        }
    }

    private func push(uid: String, data: AppData) async {
        guard let raw = try? Store.encoder.encode(data),
              let json = String(data: raw, encoding: .utf8) else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await docRef(uid).setData([
                "json": json,
                "updatedAt": Timestamp(date: data.updatedAt),
                "deviceId": deviceID,
                "schema": 1,
            ])
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
