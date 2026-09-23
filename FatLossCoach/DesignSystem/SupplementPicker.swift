import SwiftUI

/// A searchable supplement library used in BOTH onboarding and the Today manage sheet.
///
/// - A search field at the top filters `Plan.supplementCatalog` by name as you type.
/// - Tapping a row adds/removes it (checkmark). There is NO cap — add as many as you want.
/// - Currently-tracked supplements are pinned to the top (in tracked order) so the list reads as a set.
/// - When the query matches nothing in the catalog, a "➕ Add \"<query>\"" row adds a CUSTOM supplement.
///
/// The picker is agnostic about storage: the host passes the current tracked list and three closures.
struct SupplementPicker: View {
    /// The supplements currently tracked (catalog + custom), in tracked order.
    var tracked: [TrackedSupplement]
    /// Add/remove a CATALOG supplement by its key.
    var setCatalog: (_ key: String, _ tracked: Bool) -> Void
    /// Add a user-typed custom supplement by name.
    var addCustom: (_ name: String) -> Void
    /// Remove any tracked supplement by id (catalog or custom) — used to un-track a pinned custom row.
    var remove: (_ id: String) -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trackedIDs: Set<String> { Set(tracked.map(\.id)) }

    /// Catalog entries matching the query and not already tracked (tracked ones are shown in the pinned block).
    private var catalogResults: [Supplement] {
        let q = trimmedQuery.lowercased()
        return Plan.supplementCatalog.filter { s in
            !trackedIDs.contains(s.key) && (q.isEmpty || s.name.lowercased().contains(q))
        }
    }

    /// Tracked entries shown pinned at top, filtered by the query so search narrows both blocks together.
    private var pinnedTracked: [TrackedSupplement] {
        let q = trimmedQuery.lowercased()
        return tracked.filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    /// Show the custom-add row when there's a query that matches no catalog name and isn't already a
    /// tracked custom name (case-insensitive), so users can add anything not in the library.
    private var showCustomAdd: Bool {
        guard !trimmedQuery.isEmpty else { return false }
        let q = trimmedQuery.lowercased()
        let inCatalog = Plan.supplementCatalog.contains { $0.name.lowercased() == q }
        let alreadyTracked = tracked.contains { $0.name.lowercased() == q }
        return !inCatalog && !alreadyTracked
    }

    var body: some View {
        VStack(spacing: 10) {
            searchField
                // Debug / screenshots: `-suppQuery magn` prefills the search so a filtered / custom-add state
                // can be captured without a tap (this Mac has no simctl tap; matches the app's arg convention).
                .onAppear {
                    if query.isEmpty, let q = UserDefaults.standard.string(forKey: "suppQuery"), !q.isEmpty {
                        query = q
                    }
                }

            if pinnedTracked.isEmpty && catalogResults.isEmpty && !showCustomAdd {
                Text("No supplements match \u{201C}\(trimmedQuery)\u{201D}.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }

            if showCustomAdd {
                customAddRow
            }

            // Pinned: what the user already tracks (tap to remove).
            ForEach(pinnedTracked) { s in
                row(id: s.id, name: s.name, detail: s.detail, symbol: s.symbol, on: true) {
                    remove(s.id)
                }
            }

            // The rest of the library (tap to add).
            ForEach(catalogResults) { s in
                row(id: s.key, name: s.name, detail: s.detail, symbol: s.symbol, on: false) {
                    setCatalog(s.key, true)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
            TextField("", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .tint(Theme.primary)
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text("Search supplements")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                            .allowsHitTesting(false)
                    }
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.muted)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color(hex: 0x20292F))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0x2C3940), lineWidth: 1))
    }

    private var customAddRow: some View {
        Button {
            addCustom(trimmedQuery)
            query = ""
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.primary.opacity(0.16)).frame(width: 38, height: 38)
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \u{201C}\(trimmedQuery)\u{201D}").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Custom supplement").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xA7B6BE))
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.primary)
            }
            .padding(12)
            .background(Theme.primary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.primary, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// One catalog/tracked row — icon tile + name + optional dose/timing + a check that reflects tracked state.
    private func row(id: String, name: String, detail: String?, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.primary.opacity(0.16)).frame(width: 38, height: 38)
                    Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                    if let d = detail {
                        Text(d).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xA7B6BE))
                    }
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(on ? Theme.primary : Theme.muted)
            }
            .padding(12)
            .background(on ? Theme.primary.opacity(0.10) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? Theme.primary : Theme.border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
