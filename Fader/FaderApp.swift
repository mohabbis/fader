#if os(macOS)
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

#endif


#if !os(macOS)
@main
enum FaderMain {
    static func main() {
        print("Fader runs on macOS 14.2 or later.")
    }
}
#endif
