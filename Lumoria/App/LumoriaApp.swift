import SwiftUI

@main
struct LumoriaApp: App {
    @State private var store = SitesStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(.signalText)
                .task { await store.load() }
        }
    }
}

enum Route: Hashable {
    case moon(selected: String?)
    case archive
}

struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .moon(let selected): MoonView(initialSelection: selected)
                    case .archive: ArchiveView(path: $path)
                    }
                }
        }
    }
}
