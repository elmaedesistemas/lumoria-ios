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
    case sky
    case skyCamera
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
                    case .sky: SkyView()
                    case .skyCamera: SkyCameraView()
                    }
                }
        }
        #if DEBUG
        .onAppear {
            // `-LumoriaOpenTable YES` / `-LumoriaOpenSky YES` open a mode directly, for checking AR on a device.
            if UserDefaults.standard.bool(forKey: "LumoriaOpenTable") { path = [.moon(selected: nil)] }
            if UserDefaults.standard.bool(forKey: "LumoriaOpenSky") { path = [.sky, .skyCamera] }
        }
        #endif
    }
}
