import SwiftUI

@main
struct FaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(engine: delegate.engine, showsOpenButton: true)
        } label: {
            Image(systemName: "slider.vertical.3")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = AudioEngine()

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}
