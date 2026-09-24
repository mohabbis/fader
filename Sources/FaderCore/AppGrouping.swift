import Foundation

/// Chrome, Electron, and Zoom split audio across helper processes.
/// One fader should represent the app a person recognizes.
public func appGroupKey(bundleID: String?, processName: String) -> String {
    let trimmedName = processName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var bundle = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !bundle.isEmpty else {
        return "name:\(trimmedName.isEmpty ? "unknown" : trimmedName)"
    }

    let markers = [".helper", ".xpc", ".agent"]
    var changed = true
    while changed {
        changed = false
        for marker in markers {
            guard let range = bundle.range(of: marker, options: .caseInsensitive) else { continue }
            bundle = String(bundle[..<range.lowerBound])
            changed = true
            break
        }
    }
    return bundle.isEmpty ? "name:\(trimmedName.isEmpty ? "unknown" : trimmedName)" : bundle
}

public func friendlyAppName(groupKey: String, processNames: [String]) -> String {
    if groupKey.hasPrefix("name:") {
        let raw = String(groupKey.dropFirst(5))
        return cleanedProcessName(raw)
    }
    if let name = processNames.map(cleanedProcessName).first(where: { !$0.isEmpty }) {
        return name
    }
    return groupKey
}

public func cleanedProcessName(_ name: String) -> String {
    var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let suffixes = [" Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)", " Helper", " (Renderer)"]
    var changed = true
    while changed {
        changed = false
        for suffix in suffixes where result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count))
            changed = true
        }
    }
    return result
}
