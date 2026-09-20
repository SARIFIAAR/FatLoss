import SwiftUI

/// Connect Whoop / Oura via their cloud API (for the HRV + scores Apple Health can't carry).
/// Signed-in users tap Connect → vendor login → we pull data straight into the dashboard.
struct WearableConnectCard: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var cloud
    @Environment(WearableLink.self) private var link

    private static let meta: [String: (name: String, note: String)] = [
        "whoop": ("WHOOP", "HRV, recovery, sleep & workouts — the data WHOOP won't send to Apple Health."),
        "oura":  ("Oura",  "HRV, readiness, sleep stages & SpO₂ straight from Oura Cloud."),
    ]

    var body: some View {
        Card {
            Text("Connect a wearable").font(Theme.scoreS).foregroundStyle(Theme.primary)
                .padding(.bottom, 4)
            Text("Pulls HRV and each device's own scores directly — so Recovery & Stress run at full accuracy, not estimated.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineSpacing(3)
                .padding(.bottom, 6)

            if !cloud.isSignedIn {
                Text("Sign in with Apple above (Cloud Backup & Sync) to link a wearable.")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.orange)
                    .padding(.top, 4)
            } else {
                ForEach(WearableLink.vendors, id: \.self) { v in row(v) }
            }
            if let e = link.lastError {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.top, 6)
            }
        }
        .task { await link.refreshStatus() }
    }

    @ViewBuilder private func row(_ vendor: String) -> some View {
        let m = Self.meta[vendor] ?? (vendor.capitalized, "")
        let st = link.status[vendor]
        let busy = link.busy == vendor
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                    Text(m.note).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if st?.linked == true {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.primary)
                }
            }
            if st?.configured == false {
                Text("Coming soon — server not yet configured for \(m.name).")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else if st?.linked == true {
                HStack(spacing: 8) {
                    Button(busy ? "Syncing…" : "Sync now") { Task { await link.sync(vendor, store: store) } }
                        .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(busy)
                    Button("Disconnect") { Task { await link.unlink(vendor) } }
                        .buttonStyle(SecondaryButtonStyle()).disabled(busy)
                }
            } else {
                Button(busy ? "Connecting…" : "Connect \(m.name)") { Task { await link.connect(vendor, store: store) } }
                    .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(busy)
            }
        }
        .padding(.vertical, 8)
        if vendor != WearableLink.vendors.last { Divider().overlay(Theme.border) }
    }
}
