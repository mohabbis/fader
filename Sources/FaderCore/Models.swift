import Foundation

public struct AppRoute: Codable, Equatable, Sendable {
    public var volume: Double
    public var isMuted: Bool
    /// nil means follow the current system output.
    public var outputDeviceUID: String?
    public var outputDeviceName: String?

    public init(
        volume: Double = 1,
        isMuted: Bool = false,
        outputDeviceUID: String? = nil,
        outputDeviceName: String? = nil
    ) {
        self.volume = volume
        self.isMuted = isMuted
        self.outputDeviceUID = outputDeviceUID
        self.outputDeviceName = outputDeviceName
    }

    public static let followSystem = AppRoute()
}

public struct SavedRoutes: Codable, Equatable, Sendable {
    public var masterVolume: Double
    public var apps: [String: AppRoute]

    public init(masterVolume: Double = 1, apps: [String: AppRoute] = [:]) {
        self.masterVolume = masterVolume
        self.apps = apps
    }
}

public struct RouteDevice: Equatable, Sendable, Identifiable {
    public var uid: String
    public var name: String
    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

public struct ResolvedRoute: Equatable, Sendable {
    public var deviceUID: String?
    public var deviceName: String
    public var followsSystem: Bool
    public var isFallback: Bool
    public var missingDeviceName: String?

    public init(
        deviceUID: String?,
        deviceName: String,
        followsSystem: Bool,
        isFallback: Bool,
        missingDeviceName: String? = nil
    ) {
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.followsSystem = followsSystem
        self.isFallback = isFallback
        self.missingDeviceName = missingDeviceName
    }
}
