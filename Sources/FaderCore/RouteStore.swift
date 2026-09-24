import Foundation

public final class RouteStore: @unchecked Sendable {
    public let fileURL: URL
    public private(set) var state: SavedRoutes

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.state = Self.load(from: fileURL)
    }

    public static func applicationSupportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Fader", isDirectory: true)
            .appendingPathComponent("routes.json")
    }

    public func route(for key: String) -> AppRoute {
        state.apps[key] ?? .followSystem
    }

    public func setMasterVolume(_ volume: Double) {
        state.masterVolume = RoutingPolicy.clamp(volume)
        save()
    }

    public func update(_ key: String, _ mutate: (inout AppRoute) -> Void) {
        var route = state.apps[key] ?? .followSystem
        mutate(&route)
        route.volume = RoutingPolicy.clamp(route.volume)
        state.apps[key] = route
        save()
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> SavedRoutes {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SavedRoutes.self, from: data) else {
            return SavedRoutes()
        }
        var state = decoded
        state.masterVolume = RoutingPolicy.clamp(state.masterVolume)
        for key in state.apps.keys {
            let volume = RoutingPolicy.clamp(state.apps[key]?.volume ?? 1)
            state.apps[key]?.volume = volume
        }
        return state
    }
}
