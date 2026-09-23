import SwiftUI
import PhotosUI
import UIKit

/// Progress-photos card on the Progress tab: a chronological grid of body photos by date, a first-vs-latest
/// compare, add (camera or library) / delete, and a clear on-device privacy line. Photos are stored on-device
/// only (PhotoStore) and never uploaded. Empty state prompts the first photo.
struct ProgressPhotosCard: View {
    @Environment(Store.self) private var store
    @State private var showTimeline = false
    @State private var showAdd = false

    var body: some View {
        let photos = store.progressPhotosOnDevice
        Card {
            HStack {
                Text("PROGRESS PHOTOS").font(.system(size: 12, weight: .bold)).kerning(0.8).foregroundStyle(Theme.muted)
                Spacer()
                if !photos.isEmpty {
                    Button { showTimeline = true } label: {
                        HStack(spacing: 3) {
                            Text("See all").font(.system(size: 12, weight: .bold))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }.foregroundStyle(Theme.primary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)

            if photos.isEmpty {
                emptyState
            } else {
                // First-vs-latest compare strip when there are at least two.
                if photos.count >= 2 {
                    CompareStrip(first: photos.first!, latest: photos.last!)
                        .padding(.bottom, 12)
                }
                // A short horizontal preview of the most recent photos.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.suffix(6).reversed()) { p in
                            PhotoThumb(photo: p, side: 84)
                        }
                    }
                }
                Button { showAdd = true } label: {
                    Label("Add photo", systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 12)
            }

            PrivacyLine().padding(.top, 12)
        }
        .sheet(isPresented: $showTimeline) { ProgressPhotoTimelineView() }
        .sheet(isPresented: $showAdd) { AddProgressPhotoSheet() }
        .task {
            // Debug/QA (screenshots): deep-link into the timeline or add sheet, matching the app's dash-arg
            // convention. `-progressTimeline 1` opens the full timeline; `-progressAdd 1` opens the add sheet.
            if UserDefaults.standard.bool(forKey: "progressTimeline") { showTimeline = true }
            if UserDefaults.standard.bool(forKey: "progressAdd") { showAdd = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 34, weight: .light)).foregroundStyle(Theme.muted.opacity(0.6))
            Text("Track how your body changes")
                .font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
            Text("Add a photo now, then another every couple of weeks. The change is easier to see than to feel.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { showAdd = true } label: { Label("Add first photo", systemImage: "camera.fill") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

/// The mandatory, factual privacy assurance: photos sync to the user's own private account (owner-only).
struct PrivacyLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.muted)
            Text("Your photos sync privately to your account.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Thumbnails & compare

/// A rounded square thumbnail for one photo; taps to a full viewer. Renders a missing-file placeholder for
/// metadata whose bytes aren't on this device (e.g. synced from another device).
/// Loads a photo's image from disk (fill), or a neutral placeholder when the file isn't on this device
/// (a metadata-only entry synced from another device). Single source of truth for the missing-file tile.
struct PhotoImage: View {
    let filename: String

    var body: some View {
        if let img = PhotoStore.load(filename) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Rectangle().fill(Theme.card2)
                .overlay(Image(systemName: "photo").foregroundStyle(Theme.muted))
        }
    }
}

struct PhotoThumb: View {
    let photo: ProgressPhoto
    var side: CGFloat = 84
    @State private var showFull = false

    var body: some View {
        Button { showFull = true } label: {
            ZStack(alignment: .bottomLeading) {
                PhotoImage(filename: photo.filename)
                Text(shortDate(photo.date))
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(5)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFull) { PhotoFullView(photo: photo) }
    }
}

/// First-vs-latest side-by-side comparison.
struct CompareStrip: View {
    let first: ProgressPhoto
    let latest: ProgressPhoto

    var body: some View {
        HStack(spacing: 8) {
            comparePane(first, label: "First")
            Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            comparePane(latest, label: "Latest")
        }
    }

    private func comparePane(_ p: ProgressPhoto, label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let img = PhotoStore.load(p.filename) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.card2)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.muted))
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(spacing: 0) {
                Text("\(label) · \(shortDate(p.date))").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                if let w = p.weightKg { Text("\(Fmt.num(w)) kg").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.text) }
            }
        }
    }
}

// MARK: - Full viewer

struct PhotoFullView: View {
    let photo: ProgressPhoto
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let img = PhotoStore.load(photo.filename) {
                        Image(uiImage: img).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.card2).frame(height: 320)
                            .overlay(Text("Downloading…").font(.system(size: 13)).foregroundStyle(Theme.muted))
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(longDate(photo.date)).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.text)
                            if let w = photo.weightKg { Text("\(Fmt.num(w)) kg").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                    }
                    if let note = photo.note, !note.isEmpty {
                        Text(note).font(.system(size: 13)).foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete photo", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    PrivacyLine()
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Progress photo").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .alert("Delete this photo?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { store.deleteProgressPhoto(photo.id); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The photo is removed from this device. This can't be undone.")
            }
        }
    }
}

// MARK: - Full timeline

struct ProgressPhotoTimelineView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                let photos = store.progressPhotosOnDevice
                VStack(alignment: .leading, spacing: 12) {
                    if photos.count >= 2 {
                        Card {
                            SectionTitle("First vs Latest")
                            CompareStrip(first: photos.first!, latest: photos.last!)
                        }
                    }
                    // Newest first, grouped by date section.
                    ForEach(sections(photos), id: \.date) { section in
                        Text(longDate(section.date)).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(section.photos) { p in PhotoThumb(photo: p, side: 108) }
                        }
                    }
                    PrivacyLine().padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Progress photos").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showAdd) { AddProgressPhotoSheet() }
        }
    }

    private struct DateSection { let date: String; let photos: [ProgressPhoto] }
    private func sections(_ photos: [ProgressPhoto]) -> [DateSection] {
        let grouped = Dictionary(grouping: photos) { $0.date }
        return grouped.keys.sorted(by: >).map { DateSection(date: $0, photos: grouped[$0]!.sorted { $0.at > $1.at }) }
    }
}

// MARK: - Add sheet (camera or library)

struct AddProgressPhotoSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var note = ""
    @State private var attachWeight = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.card2).frame(height: 240)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.viewfinder").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.muted)
                                    Text("Take or choose a photo").font(.system(size: 13)).foregroundStyle(Theme.muted)
                                }
                            }
                    }

                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                            Label("Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.muted)
                                .padding(.vertical, 13).background(Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 2))
                        }
                    }

                    if image != nil {
                        VStack(spacing: 10) {
                            if let w = store.currentWeight {
                                Toggle(isOn: $attachWeight) {
                                    Text("Attach today's weight (\(Fmt.num(w)) kg)").font(.system(size: 13)).foregroundStyle(Theme.text)
                                }.tint(Theme.primary)
                            }
                            TextField("Note (optional)", text: $note, axis: .vertical)
                                .font(.system(size: 14)).foregroundStyle(Theme.text)
                                .padding(12).background(Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 2))
                            Button {
                                store.addProgressPhoto(image!, weightKg: attachWeight ? store.currentWeight : nil,
                                                       note: note)
                                dismiss()
                            } label: { Text("Save photo").frame(maxWidth: .infinity) }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }

                    PrivacyLine()
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Add progress photo").navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) {
                // Reuse the Nutrition scanner's camera wrapper (callback is UIImage?); dismiss on result.
                CameraPicker { img in if let img { image = img }; showCamera = false }.ignoresSafeArea()
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        image = img
                    }
                }
            }
        }
    }
}

// Camera capture reuses `CameraPicker` from NutritionView (UIImagePickerController wrapper).

// MARK: - Date helpers

private func shortDate(_ key: String) -> String {
    guard let d = DateKey.date(key) else { return key }
    return d.formatted(.dateTime.month(.abbreviated).day())
}
private func longDate(_ key: String) -> String {
    guard let d = DateKey.date(key) else { return key }
    return d.formatted(.dateTime.month(.wide).day().year())
}
