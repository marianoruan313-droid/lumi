import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var store: PhotoStore
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CaptureRecord?
    @State private var showFavorites = false

    private var records: [CaptureRecord] { showFavorites ? store.records.filter { favorites.ids.contains($0.profile.id) } : store.records }

    var body: some View {
        NavigationStack {
            ScrollView {
                if records.isEmpty {
                    ContentUnavailableView("No photos yet", systemImage: "photo", description: Text("Take your first picture in Lumi Camera."))
                        .padding(.top, 70)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(records) { record in
                            Button { selected = record } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    let file = record.processedFile ?? record.originalFile
                                    if let image = store.thumbnail(file) { Image(uiImage: image).resizable().scaledToFill().frame(height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                                    Text(record.profile.name).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text(record.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(12)
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { showFavorites.toggle() } label: { Image(systemName: showFavorites ? "heart.fill" : "heart") } }
            }
            .fullScreenCover(item: $selected) { PhotoDetailView(record: $0).environmentObject(store).environmentObject(favorites) }
        }
    }
}

struct PhotoDetailView: View {
    @EnvironmentObject private var store: PhotoStore
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss
    let record: CaptureRecord
    @State private var showingOriginal = false
    @State private var replacement: CameraProfile?
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("View", selection: $showingOriginal) { Text("Processed").tag(false); Text("Original").tag(true) }.pickerStyle(.segmented)
                let file = showingOriginal ? record.originalFile : (record.processedFile ?? record.originalFile)
                if let image = store.image(file) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: .infinity) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.profile.name).font(.headline)
                    Text(record.date.formatted(date: .long, time: .short)).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu("Reprocess with another camera") {
                    ForEach(ProfileLibrary.all) { profile in Button(profile.name) { replacement = profile; reprocess(profile) } }
                }.disabled(busy)
            }.padding()
            .navigationTitle("Photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { favorites.toggle(record.profile.id) } label: { Image(systemName: favorites.ids.contains(record.profile.id) ? "heart.fill" : "heart") } }
                ToolbarItem(placement: .bottomBar) { Button(role: .destructive) { store.delete(record); dismiss() } label: { Label("Delete", systemImage: "trash") } }
            }
            .alert("Lumi Camera", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK") { errorText = nil } } message: { Text(errorText ?? "") }
        }
    }

    private func reprocess(_ profile: CameraProfile) {
        busy = true
        Task { do { try await store.reprocess(record, with: profile); busy = false } catch { busy = false; errorText = error.localizedDescription } }
    }
}
