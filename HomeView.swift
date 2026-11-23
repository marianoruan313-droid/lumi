import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: PhotoStore
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var search = ""
    @State private var category: CameraCategory?
    @State private var favoritesOnly = false
    @State private var selectedProfile: CameraProfile?
    @State private var showGallery = false

    private var filtered: [CameraProfile] {
        ProfileLibrary.all.filter { profile in
            (category == nil || profile.category == category) &&
            (!favoritesOnly || favorites.ids.contains(profile.id)) &&
            (search.isEmpty || profile.name.localizedCaseInsensitiveContains(search) || profile.tagline.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    featured
                    searchBar
                    categoryPicker
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(filtered) { profile in profileCard(profile) }
                    }
                }.padding(16)
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .fullScreenCover(item: $selectedProfile) { CameraView(profile: $0) }
            .sheet(isPresented: $showGallery) { GalleryView().environmentObject(store).environmentObject(favorites) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LUMI").font(.system(size: 30, weight: .black, design: .rounded)).tracking(3)
                Text("CAMERA COLLECTION").font(.caption2.weight(.medium)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showGallery = true } label: {
                Image(systemName: "square.grid.2x2").font(.title3).padding(12)
                    .background(.white.opacity(0.09), in: Circle())
            }
        }
    }

    private var featured: some View {
        Button { selectedProfile = ProfileLibrary.all.first } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Color(red: 0.28, green: 0.25, blue: 0.20), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR POCKET CAMERA").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.7))
                    Text("Capture a feeling.").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("15 original camera recipes · real camera capture").font(.caption).foregroundStyle(.white.opacity(0.75))
                }.padding(22)
                Image(systemName: "camera.aperture").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(.white.opacity(0.14)).offset(x: 90, y: -15)
            }.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search cameras", text: $search)
            Button { favoritesOnly.toggle() } label: { Image(systemName: favoritesOnly ? "heart.fill" : "heart").foregroundStyle(favoritesOnly ? .pink : .secondary) }
        }.padding(12).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip("All", selected: category == nil) { category = nil }
                ForEach(CameraCategory.allCases) { c in categoryChip(c.rawValue, selected: category == c) { category = c } }
            }
        }
    }

    private func categoryChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 9)
            .background(selected ? Color.white : Color.white.opacity(0.08), in: Capsule()).foregroundStyle(selected ? Color.black : Color.white) }
    }

    private func profileCard(_ p: CameraProfile) -> some View {
        Button { selectedProfile = p } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(cardColor(p)).frame(height: 132)
                    Image(systemName: icon(p)).font(.system(size: 46, weight: .ultraLight)).foregroundStyle(.white.opacity(0.75))
                    VStack { HStack { Text(p.category.rawValue.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1).padding(7).background(.black.opacity(0.25), in: Capsule()); Spacer()
                        Button { favorites.toggle(p.id) } label: { Image(systemName: favorites.ids.contains(p.id) ? "heart.fill" : "heart").foregroundStyle(favorites.ids.contains(p.id) ? .pink : .white).padding(6) }.buttonStyle(.plain)
                    }; Spacer(); HStack { Text(p.era).font(.caption2).foregroundStyle(.white.opacity(0.65)); Spacer() } }.padding(10)
                }
                Text(p.name).font(.subheadline.weight(.bold)).lineLimit(1)
                Text(p.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .top)
            }
        }.buttonStyle(.plain)
    }

    private func icon(_ p: CameraProfile) -> String {
        switch p.category { case .instant: return "photo"; case .film: return "camera.macro"; case .night, .flash: return "bolt.fill"; case .portrait: return "person.crop.square"; default: return "camera" }
    }
    private func cardColor(_ p: CameraProfile) -> Color {
        switch p.category { case .instant: return Color(red: 0.38, green: 0.28, blue: 0.24); case .film: return Color(red: 0.24, green: 0.31, blue: 0.25); case .night, .flash: return Color(red: 0.22, green: 0.25, blue: 0.38); case .portrait: return Color(red: 0.38, green: 0.28, blue: 0.32); default: return Color(red: 0.29, green: 0.32, blue: 0.34) }
    }
}
