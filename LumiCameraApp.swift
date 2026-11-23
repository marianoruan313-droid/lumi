import SwiftUI

@main
struct LumiCameraApp: App {
    @StateObject private var photoStore = PhotoStore()
    @StateObject private var favorites = FavoritesStore()
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(photoStore)
                .environmentObject(favorites)
                .preferredColorScheme(.dark)
        }
    }
}
