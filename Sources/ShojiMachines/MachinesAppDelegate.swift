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

    private var signalSources: [DispatchSourceSignal] = []
    /// A signal (kill, logout) asked us to quit: no question, just a clean shutdown.
    private var quittingFromSignal = false
    /// A quit is under way (VMs shutting down); further quit requests are ignored.
    private var quitting = false
    /// The "Quit Shoji Machines?" question is on screen.
    private var askingToQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // (One Shoji Machines per VMs folder: main.swift takes the folder's lock before launching.)
        // `kill` / logout: quit properly, so running VMs get a clean shutdown.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in self?.signalReceived() }
            src.resume()
            signalSources.append(src)
            // If the main thread is stuck, a signal handled on it would never run: the watchdog
            // below exits anyway (installed on the first signal, from a background queue).
            let watchdog = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            watchdog.setEventHandler { Self.armWatchdog() }
            watchdog.resume()
            signalSources.append(watchdog)
        }
        Config.shared.load()
        buildMenus()
        machines = MachinesApp()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 560),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Machines"
        window.contentView = machines.view
        window.isReleasedWhenClosed = false
        // See-through like the terminals: the view draws its own (translucent) background.
        window.isOpaque = false
        window.backgroundColor = .clear
        applyTitlebar()
        NotificationCenter.default.addObserver(forName: .configDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTitlebar() }
        }
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

    /// Like kitty with hide_window_decorations titlebar-only: no title bar or traffic lights, but
    /// still resizable (and movable by its background, though Shoji places it anyway).
    private func applyTitlebar() {
        let hide = Config.shared.hideTitlebar
        if hide { window.styleMask.insert(.fullSizeContentView) } else { window.styleMask.remove(.fullSizeContentView) }
        window.titlebarAppearsTransparent = hide
        window.titleVisibility = hide ? .hidden : .visible
        window.isMovableByWindowBackground = hide
        window.contentView?.needsLayout = true // content moves below (or up into) the title bar area
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = hide
        }
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
        guard !quitting else { return .terminateCancel } // already shutting down; that quit finishes
        let running = VMManager.shared.running.count
        guard running > 0 else { return .terminateNow }
        if ProcessInfo.processInfo.environment["SHOJI_MACHINES_TEST"] == nil, !quittingFromSignal {
            let alert = NSAlert()
            alert.messageText = "Quit Shoji Machines?"
            alert.informativeText = "\(running) running VM\(running == 1 ? "" : "s") will be shut down."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            askingToQuit = true
            let answer = alert.runModal()
            askingToQuit = false
            // A signal while the question was up answers it: quit.
            guard answer == .alertFirstButtonReturn || quittingFromSignal else { return .terminateCancel }
        }
        quitting = true
        // Clean shutdown first (timers run in .common mode, so they fire while we wait).
        VMManager.shared.stopAll { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    private func signalReceived() {
        guard !quitting else { return } // a second kill / logout's SIGHUP after SIGTERM
        quittingFromSignal = true
        if askingToQuit {
            NSApp.abortModal() // the open "Quit?" question counts as answered (see above)
        } else {
            NSApp.terminate(nil)
        }
    }

    /// Exit even if the main thread never gets to the clean shutdown — longer than the slowest
    /// clean VM stop (15 s request + forced stop), so a working quit always finishes first.
    nonisolated private static func armWatchdog() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { exit(0) }
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
