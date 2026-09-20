import Foundation
import AuthenticationServices
import FirebaseAuth

/// Client for the "Path B" wearable cloud integrations (Whoop, Oura) served by our Fly backend.
/// Flow: ask the server for the vendor's OAuth URL → run it in an ASWebAuthenticationSession →
/// the server's callback bounces back to `fatlosscoach://wearable` → we then pull normalised data
/// and merge it into the Store (so it flows through the same BodyMetrics engine as Apple Health).
@Observable
@MainActor
final class WearableLink: NSObject {
    static let base = URL(string: "https://fatloss-analyzer.fly.dev")!
    static let vendors = ["whoop", "oura"]

    struct Status: Decodable { var configured: Bool; var linked: Bool; var lastSyncAt: Double? }

    var status: [String: Status] = [:]
    var busy: String? = nil            // vendor currently connecting/syncing
    var lastError: String? = nil

    // MARK: normalised sync payload (mirror of integrations.js output)

    struct Sync: Decodable {
        var vendor: String
        var days: [String: Day]
        var workouts: [Work]
        struct Day: Decodable { var hrv, rhr, sleepH, deepH, remH, resp, spo2: Double? }
        struct Work: Decodable { var date: String; var name: String?; var kcal: Double?; var minutes: Double?; var avgHR: Double? }
    }

    private func token() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw Err.notSignedIn }
        return try await user.getIDToken()
    }

    private func authed(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: Self.base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw Err.server(msg ?? "Request failed")
        }
        return data
    }

    // MARK: status

    func refreshStatus() async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            let data = try await authed("connect/status")
            let wrap = try JSONDecoder().decode([String: [String: Status]].self, from: data)
            status = wrap["vendors"] ?? [:]
        } catch { /* leave prior status; surfaced elsewhere */ }
    }

    // MARK: connect (OAuth)

    func connect(_ vendor: String, store: Store) async {
        busy = vendor; lastError = nil
        defer { busy = nil }
        do {
            let urlData = try await authed("connect/\(vendor)/url")
            guard let auth = (try? JSONDecoder().decode([String: String].self, from: urlData))?["url"],
                  let authURL = URL(string: auth) else { throw Err.server("Couldn't start \(vendor) sign-in.") }
            _ = try await runOAuth(authURL)      // returns the fatlosscoach://wearable callback
            await refreshStatus()
            await sync(vendor, store: store)     // initial pull
        } catch {
            if case Err.cancelled = error { return }
            lastError = friendly(error)
        }
    }

    /// Runs the vendor login in a system web session; resolves with the app-scheme callback URL.
    private func runOAuth(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "fatlosscoach") { cb, err in
                if let cb { cont.resume(returning: cb) }
                else if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin { cont.resume(throwing: Err.cancelled) }
                else { cont.resume(throwing: err ?? Err.server("Sign-in failed.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() { cont.resume(throwing: Err.server("Couldn't open the sign-in window.")) }
        }
    }

    // MARK: sync / unlink

    func sync(_ vendor: String, store: Store, days: Int = 30) async {
        busy = vendor; lastError = nil
        defer { busy = nil }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["days": days])
            let data = try await authed("connect/\(vendor)/sync", method: "POST", body: body)
            let payload = try JSONDecoder().decode(Sync.self, from: data)
            store.applyWearable(vendor: payload.vendor, days: payload.days, workouts: payload.workouts)
            await refreshStatus()
        } catch { lastError = friendly(error) }
    }

    func unlink(_ vendor: String) async {
        do { _ = try await authed("connect/\(vendor)/unlink", method: "POST", body: Data("{}".utf8)); await refreshStatus() }
        catch { lastError = friendly(error) }
    }

    // MARK: errors

    enum Err: Error { case notSignedIn, cancelled, server(String) }
    private func friendly(_ e: Error) -> String {
        if case Err.server(let m) = e { return m }
        if case Err.notSignedIn = e { return "Sign in with Apple first (Profile → Cloud sync)." }
        return e.localizedDescription
    }
}

extension WearableLink: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
