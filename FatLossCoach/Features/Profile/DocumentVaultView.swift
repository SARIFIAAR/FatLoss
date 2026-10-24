import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// Personal health-document vault (E1-02). A private, Face ID-gated container for the user's OWN records —
/// lab reports, InBody printouts, scans. Add by PDF import or photo; view with QuickLook; delete removes it
/// everywhere (device + cloud). Bytes live in `DocStore` (encrypted at rest) + Firebase Storage (owner-only).
///
/// RA boundary (concierge-guardrails sibling rule): HUMANS is a *container* here — it stores and displays
/// the user's documents and NEVER reads, parses, or interprets their contents. No OCR, no "your LDL is high".
struct DocumentVaultView: View {
    @Environment(Store.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss

    @State private var unlocked = false
    @State private var gateFailed = false
    @State private var showPDFImporter = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var pending: PendingDoc?
    @State private var previewURL: URL?

    /// Picked-but-not-yet-saved bytes awaiting a title + category.
    struct PendingDoc: Identifiable { let id = UUID(); let data: Data; let contentType: String; var suggestedTitle: String }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if unlocked { vault } else { gate }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.muted)
            }
            .padding(.trailing, 16).padding(.top, 10)
        }
        .onAppear { if !unlocked { authenticate() } }
        .sheet(item: $pending) { p in AddDocumentSheet(pending: p) }
        .quickLookPreview($previewURL)
    }

    // MARK: Gate

    private func authenticate() {
        // QA bypass for simulator screenshots (`-vaultPreview 1`), without locking the whole app.
        if lock.previewMode || UserDefaults.standard.bool(forKey: "vaultPreview") { unlocked = true; return }
        lock.authenticate(reason: "Unlock your health documents") { ok in
            unlocked = ok
            gateFailed = !ok
        }
    }

    private var gate: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc.fill").font(.system(size: 44)).foregroundStyle(Theme.primary)
            Text("Your documents are locked").font(Theme.titleL).foregroundStyle(Theme.text)
            Text("Unlock with \(lock.biometryName) to view your private health records.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { authenticate() } label: {
                Label(gateFailed ? "Try again" : "Unlock", systemImage: lock.biometrySymbol)
            }
            .buttonStyle(PillButtonStyle()).padding(.top, 6)
        }
        .padding(32)
    }

    // MARK: Vault

    private var vault: some View {
        Screen(subtitle: "Private · Face ID", title: "Health Documents") {
            addMenu
            let docs = store.documents
            if docs.isEmpty {
                emptyState
            } else {
                Card {
                    ForEach(Array(docs.enumerated()), id: \.element.id) { i, doc in
                        if i > 0 { Divider().overlay(Theme.border).padding(.vertical, 6) }
                        row(doc)
                    }
                }
            }
            Text("HUMANS keeps these documents private on your device and in your own cloud space. It never reads or interprets their contents.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 2)
        }
    }

    private var addMenu: some View {
        Menu {
            Button { showPDFImporter = true } label: { Label("Add a PDF", systemImage: "doc.fill") }
            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                Label("Add a photo", systemImage: "photo.fill")
            }
        } label: {
            Label("Add a document", systemImage: "plus.circle.fill")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.primary).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
            guard case let .success(url) = result else { return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { store.showToast("Couldn't read that PDF"); return }
            pending = PendingDoc(data: data, contentType: "application/pdf",
                                 suggestedTitle: url.deletingPathExtension().lastPathComponent)
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let ct = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
                    await MainActor.run { pending = PendingDoc(data: data, contentType: ct, suggestedTitle: "") }
                }
                await MainActor.run { pickedPhoto = nil }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36)).foregroundStyle(Theme.muted)
            Text("No documents yet").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
            Text("Add your blood tests, body-composition reports and scans so they live with the rest of your health data.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private func row(_ doc: HealthDoc) -> some View {
        let onDevice = DocStore.exists(doc.filename)
        return Button {
            guard onDevice else { store.showToast("Still downloading…"); return }
            previewURL = DocStore.url(for: doc.filename)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: doc.category.icon).font(.system(size: 16)).foregroundStyle(Theme.primary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text("\(doc.category.label) · \(doc.at.formatted(date: .abbreviated, time: .omitted)) · \(doc.sizeLabel)")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: onDevice ? (doc.isPDF ? "doc.richtext" : "photo") : "arrow.down.circle")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { store.deleteDocument(doc.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// Collects a title + category for a picked document, then commits it to the vault.
private struct AddDocumentSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pending: DocumentVaultView.PendingDoc
    @State private var title = ""
    @State private var category: HealthDoc.Category = .bloods

    var body: some View {
        Screen(subtitle: "Private", title: "Save document") {
            Card {
                SectionTitle("Title")
                TextField("e.g. Blood test – Oct 2026", text: $title)
                    .textFieldStyle(.plain).foregroundStyle(Theme.text)
                    .padding(10).background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))

                SectionTitle("Category").padding(.top, 8)
                Picker("Category", selection: $category) {
                    ForEach(HealthDoc.Category.allCases, id: \.self) { c in Text(c.label).tag(c) }
                }
                .pickerStyle(.menu).tint(Theme.primary)

                Button("Save to vault") {
                    store.addDocument(data: pending.data, contentType: pending.contentType,
                                      title: title, category: category)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle()).padding(.top, 10)
            }
        }
        .onAppear { if title.isEmpty { title = pending.suggestedTitle } }
    }
}
