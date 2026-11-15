import AppKit

/// Shoji Machines: the companion app that runs Shoji's Linux VMs. It's the same program as Shoji,
/// started from its own bundle (dev.shoji.Machines, signed with the virtualization entitlement) —
/// a regular app with a Dock icon whose Machines window Shoji tiles like any other. VMs live in
/// this process, so they keep running when Shoji itself restarts.
@MainActor
final class MachinesAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    nonisolated static let bundleID = "dev.shoji.Machines"

    private var window: NSWindow!
    private var machines: MachinesApp!
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.shared.load()
        buildMenus()
        machines = MachinesApp()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 560),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Machines"
        window.contentView = machines.view
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ShojiMachines")
        if !window.setFrameUsingName("ShojiMachines") { window.center() }

        // Theme picked in Shoji (another process): reload the shared settings and recolour.
        DistributedNotificationCenter.default().addObserver(forName: Config.changedAcrossApps, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Config.shared.load()
                Config.shared.notifyChanged()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            nonisolated(unsafe) let event = e // delivered on the main thread
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.window, !(self.window.firstResponder is NSText) else { return false }
                return self.machines.handleKey(event)
            }
            return handled ? nil : e
        }
        if MachinesTest.run() { return } // scripted test (SHOJI_MACHINES_TEST), headless
        showWindow()
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        machines.focus()
    }

    // The Dock icon (or ⌥M in Shoji) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// VMs keep running with the window closed; quit from the menu (or the Dock) to stop them.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = VMManager.shared.running.count
        guard running > 0 else { return .terminateNow }
        if ProcessInfo.processInfo.environment["SHOJI_MACHINES_TEST"] == nil {
            let alert = NSAlert()
            alert.messageText = "Quit Shoji Machines?"
            alert.informativeText = "\(running) running VM\(running == 1 ? "" : "s") will be shut down."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        // Clean shutdown first (timers run in .common mode, so they fire while we wait).
        VMManager.shared.stopAll { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        machines?.shutdown()
    }

    private func buildMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Shoji Machines", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Shoji Machines", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Shoji Machines", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Machines", action: #selector(showMachines), keyEquivalent: "0").target = self
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = win
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    @objc private func showMachines() { showWindow() }
}
