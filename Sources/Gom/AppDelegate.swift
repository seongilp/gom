import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PlayerWindowController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()

        let controller = PlayerWindowController()
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !pendingURLs.isEmpty {
            controller.open(urls: pendingURLs)
            pendingURLs.removeAll()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let controller = windowController {
            controller.open(urls: urls)
        } else {
            pendingURLs = urls
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func openDocument(_ sender: Any?) {
        windowController?.presentOpenPanel()
    }
}
