import SwiftUI
import SwiftData

@main
struct TripAtlasApp: App {
    @State private var importer = TripImporter()
    @State private var boundaries = BoundaryStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(importer)
                .environment(boundaries)
        }
        .modelContainer(for: [Trip.self, DismissedSuggestion.self])
    }
}
