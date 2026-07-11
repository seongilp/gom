import AppKit

enum MainMenu {
    private static var recentMenu: NSMenu?

    static func install() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Gom",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Gom",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Gom",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open…",
                         action: #selector(AppDelegate.openDocument(_:)),
                         keyEquivalent: "o")

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recent = NSMenu(title: "Open Recent")
        recentItem.submenu = recent
        recentMenu = recent
        fileMenu.addItem(recentItem)

        fileMenu.addItem(.separator())
        let previousItem = NSMenuItem(
            title: "Previous File",
            action: #selector(PlayerWindowController.previousFile(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        )
        previousItem.keyEquivalentModifierMask = .command
        fileMenu.addItem(previousItem)
        let nextItem = NSMenuItem(
            title: "Next File",
            action: #selector(PlayerWindowController.nextFile(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        )
        nextItem.keyEquivalentModifierMask = .command
        fileMenu.addItem(nextItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")

        // Playback menu (shortcuts are handled by the player view; menu mirrors them)
        let playbackMenuItem = NSMenuItem()
        mainMenu.addItem(playbackMenuItem)
        let playbackMenu = NSMenu(title: "Playback")
        playbackMenuItem.submenu = playbackMenu
        playbackMenu.addItem(withTitle: "Play / Pause  (Space)",
                             action: #selector(PlayerWindowController.togglePlayPauseAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(withTitle: "Increase Speed  ( ] )",
                             action: #selector(PlayerWindowController.increaseSpeedAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Decrease Speed  ( [ )",
                             action: #selector(PlayerWindowController.decreaseSpeedAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Normal Speed  ( \\ )",
                             action: #selector(PlayerWindowController.resetSpeedAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(withTitle: "Next Frame  ( . )",
                             action: #selector(PlayerWindowController.frameForwardAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Previous Frame  ( , )",
                             action: #selector(PlayerWindowController.frameBackwardAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(withTitle: "Loop  (L)",
                             action: #selector(PlayerWindowController.toggleLoopAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Subtitles  (C)",
                             action: #selector(PlayerWindowController.toggleSubtitlesAction(_:)),
                             keyEquivalent: "")
        playbackMenu.addItem(withTitle: "Save Snapshot  (S)",
                             action: #selector(PlayerWindowController.snapshotAction(_:)),
                             keyEquivalent: "")

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Enter Full Screen",
                         action: #selector(NSWindow.toggleFullScreen(_:)),
                         keyEquivalent: "f")
        viewMenu.addItem(withTitle: "Always on Top  (T)",
                         action: #selector(PlayerWindowController.toggleAlwaysOnTopAction(_:)),
                         keyEquivalent: "t")
        viewMenu.addItem(withTitle: "Media Info  (V)",
                         action: #selector(PlayerWindowController.toggleInfoAction(_:)),
                         keyEquivalent: "i")
        viewMenu.addItem(withTitle: "Keyboard Shortcuts  (?)",
                         action: #selector(PlayerWindowController.toggleHelpAction(_:)),
                         keyEquivalent: "/")

        NSApp.mainMenu = mainMenu
        rebuildRecents()
    }

    static func rebuildRecents() {
        guard let recentMenu else { return }
        recentMenu.removeAllItems()
        let recents = PlaybackStore.shared.recents
        for url in recents {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(PlayerWindowController.openRecentItem(_:)),
                keyEquivalent: ""
            )
            item.representedObject = url
            recentMenu.addItem(item)
        }
        if !recents.isEmpty {
            recentMenu.addItem(.separator())
        }
        recentMenu.addItem(NSMenuItem(
            title: "Clear Menu",
            action: #selector(PlayerWindowController.clearRecentItems(_:)),
            keyEquivalent: ""
        ))
    }
}
